//
//  ProductEditView.swift
//  ShopwareApp
//
//  Edit sheet for a single product: name, price, stock, and active state are
//  staged and saved together; the image gallery (add / set cover / delete /
//  reorder) is written to Shopware immediately on each action.
//

import PhotosUI
import SwiftUI

struct ProductEditView: View {
    @ObservedObject var viewModel: ProductsViewModel
    let productID: String
    /// Called after a successful save so the list can refresh.
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var detail: ProductDetail?
    @State private var name = ""
    @State private var priceText = ""
    @State private var stock = 0
    @State private var active = true

    /// The name as loaded, to detect a real edit before writing.
    @State private var loadedName = ""

    @State private var pickedItem: PhotosPickerItem?

    /// The product's images (product_media rows), kept in sync with the server
    /// since image edits are written immediately.
    @State private var images: [ProductImage] = []
    /// product_media id currently set as the cover.
    @State private var coverID: String?
    /// Set while an image operation (upload/cover/delete/reorder) is in flight.
    @State private var imageBusy = false

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var currencyCode: String { viewModel.currencyCode }

    var body: some View {
        Group {
            if isLoading {
                Text("LOADING…")
                    .industryKicker()
                    .foregroundStyle(Color.industryFaint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                form
            }
        }
        .background(Color.industryBackground)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("EDIT PRODUCT")
                    .industryKicker(11)
                    .foregroundStyle(Color.industryText)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("SAVE") { Task { await save() } }
                    .industryKicker()
                    .foregroundStyle(Color.industryAccent)
                    .disabled(isSaving || isLoading || !isDirty)
                    .opacity(isDirty ? 1 : 0.45)
            }
        }
        .task { await load() }
        .onChange(of: pickedItem) { item in
            Task { await uploadPicked(item) }
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                BlueprintFrame {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(detail?.productNumber ?? "—")
                            .industryKicker()
                            .foregroundStyle(Color.industryFaint)
                        TextField("Product name", text: $name)
                            .font(IndustryFont.display(26))
                            .foregroundStyle(Color.industryText)
                            .textFieldStyle(.plain)
                        Rectangle().fill(Color.industryHair).frame(height: 1)
                        HStack(spacing: 0) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Gross · \(currencyCode)").industryKicker().foregroundStyle(Color.industryFaint)
                                TextField("0.00", text: $priceText)
                                    .font(IndustryFont.display(22))
                                    .textFieldStyle(.plain)
                                    .decimalKeyboard()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Rectangle().fill(Color.industryHair).frame(width: 1, height: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Net · Derived").industryKicker().foregroundStyle(Color.industryFaint)
                                Text(netDisplay)
                                    .font(IndustryFont.display(22))
                                    .foregroundStyle(Color.industryDim)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 12)
                        }
                        Text("NET DERIVED FROM GROSS AT \(detail?.taxRate?.formatted() ?? "0")% TAX")
                            .industryKicker(9)
                            .foregroundStyle(Color.industryFaint)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Inventory")
                        .padding(.bottom, 10)
                    Rectangle().fill(Color.industryLine).frame(height: 1)
                    HStack {
                        Text("Stock").font(IndustryFont.body(14.5)).foregroundStyle(Color.industryText)
                        Spacer()
                        StockStepper(stock: stock) { stock = $0 }
                    }
                    .frame(minHeight: 54)
                    Rectangle().fill(Color.industryHair).frame(height: 1)
                    HStack {
                        Text("Active in storefront").font(IndustryFont.body(14.5)).foregroundStyle(Color.industryText)
                        Spacer()
                        Text(active ? "ON" : "OFF").industryKicker().foregroundStyle(Color.industryFaint)
                        SquareToggle(isOn: $active)
                    }
                    .frame(minHeight: 54)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionHeader(title: "Images", detail: "TAP TO SET COVER")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(images) { image in galleryCell(image) }
                            PhotosPicker(selection: $pickedItem, matching: .images) {
                                Image(systemName: "plus")
                                    .font(.system(size: 18, weight: .light))
                                    .foregroundStyle(Color.industryAccent)
                                    .frame(width: 78, height: 78)
                                    .overlay(Rectangle().stroke(Color.industryLine, lineWidth: 1))
                            }
                            .disabled(imageBusy)
                        }
                    }
                    .opacity(imageBusy ? 0.45 : 1)
                }
            }
            .padding(16)
            .padding(.bottom, 28)
        }
    }

    private var isDirty: Bool {
        guard let detail else { return false }
        let typedGross = Decimal(string: priceText.replacingOccurrences(of: ",", with: "."))
        return name != loadedName ||
            stock != detail.stock ||
            active != detail.active ||
            typedGross != detail.grossPrice
    }

    /// Live net, computed from the gross the user is typing and the tax rate.
    private var netDisplay: String {
        guard let gross = Decimal(string: priceText.replacingOccurrences(of: ",", with: ".")) else {
            return "—"
        }
        let net = netFromGross(gross, taxRate: detail?.taxRate)
        return net.formatted(.number.precision(.fractionLength(2)))
    }

    @ViewBuilder
    private func galleryCell(_ image: ProductImage) -> some View {
        let isCover = image.id == coverID
        Button {
            Task { await setCover(image) }
        } label: {
            ProductThumbnail(url: image.url, size: 78)
                .overlay(alignment: .bottom) {
                    if isCover {
                        Text("COVER")
                            .industryKicker(8.5)
                            .foregroundStyle(Color.industryInverse)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.industryAccent)
                    }
                }
                .background(isCover ? Color.industryAccentTint : Color.clear)
                .overlay(Rectangle().stroke(isCover ? Color.industryAccent : Color.industryLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(imageBusy)
        .contextMenu {
            if !isCover {
                Button { Task { await setCover(image) } } label: {
                    Label("Set as cover", systemImage: "star")
                }
            }
            Button { Task { await move(image, by: -1) } } label: {
                Label("Move left", systemImage: "arrow.left")
            }
            .disabled(images.first?.id == image.id)
            Button { Task { await move(image, by: 1) } } label: {
                Label("Move right", systemImage: "arrow.right")
            }
            .disabled(images.last?.id == image.id)
            Button(role: .destructive) { Task { await delete(image) } } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Data

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let d = try await viewModel.productDetail(id: productID)
            detail = d
            name = d.name
            loadedName = d.name
            stock = d.stock
            active = d.active
            coverID = d.coverID
            if let gross = d.grossPrice {
                priceText = NSDecimalNumber(decimal: gross).stringValue
            }
            images = try await viewModel.productImages(productID: productID)
        } catch {
            errorMessage = error.shopwareDisplayMessage
        }
        isLoading = false
    }

    /// Reload just the gallery + cover from the server after an image change.
    private func reloadImages() async {
        do {
            images = try await viewModel.productImages(productID: productID)
            coverID = try await viewModel.productDetail(id: productID).coverID
        } catch {
            errorMessage = error.shopwareDisplayMessage
        }
    }

    // MARK: - Image actions (written immediately)

    private func uploadPicked(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        pickedItem = nil
        await runImageOp {
            // First image on a product becomes the cover automatically.
            try await viewModel.addProductImage(
                productID: productID,
                imageData: data,
                position: images.count,
                setAsCover: images.isEmpty
            )
        }
    }

    private func setCover(_ image: ProductImage) async {
        guard image.id != coverID else { return }
        await runImageOp {
            try await viewModel.setProductCover(productID: productID, productMediaID: image.id)
        }
    }

    private func delete(_ image: ProductImage) async {
        await runImageOp {
            try await viewModel.deleteProductImage(productMediaID: image.id)
        }
    }

    private func move(_ image: ProductImage, by offset: Int) async {
        guard let index = images.firstIndex(of: image) else { return }
        let target = index + offset
        guard images.indices.contains(target) else { return }
        var reordered = images
        reordered.swapAt(index, target)
        await runImageOp {
            try await viewModel.reorderProductImages(orderedIDs: reordered.map(\.id))
        }
    }

    /// Runs an image mutation with a busy flag, then refreshes from the server.
    private func runImageOp(_ op: @escaping () async throws -> Void) async {
        imageBusy = true
        errorMessage = nil
        do {
            try await op()
            await reloadImages()
            // Cover/thumbnail may have changed; refresh the list behind the sheet.
            onSaved()
        } catch {
            errorMessage = error.shopwareDisplayMessage
        }
        imageBusy = false
    }

    // MARK: - Save (scalar fields)

    private func save() async {
        guard let detail else { return }
        isSaving = true
        errorMessage = nil
        do {
            // Only send fields that actually changed.
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let newName = trimmedName != loadedName && !trimmedName.isEmpty ? trimmedName : nil
            let newStock = stock != detail.stock ? stock : nil

            var newGross: Decimal?
            let typedGross = Decimal(string: priceText.replacingOccurrences(of: ",", with: "."))
            if let typedGross, typedGross != detail.grossPrice {
                newGross = typedGross
            }

            try await viewModel.updateProduct(
                id: detail.id,
                name: newName,
                stock: newStock,
                grossPrice: newGross,
                taxRate: detail.taxRate,
                currencyID: detail.currencyID,
                active: active != detail.active ? active : nil
            )

            onSaved()
            dismiss()
        } catch {
            errorMessage = error.shopwareDisplayMessage
            isSaving = false
        }
    }
}

private extension View {
    /// Decimal keypad on iOS; no-op on macOS where it isn't available.
    @ViewBuilder
    func decimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }
}
