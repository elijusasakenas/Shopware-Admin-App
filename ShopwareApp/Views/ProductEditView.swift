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
    @ObservedObject var viewModel: ShopwareDashboardViewModel
    let productID: String
    /// Called after a successful save so the list can refresh.
    var onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var detail: ProductDetail?
    @State private var name = ""
    @State private var priceText = ""
    @State private var stock = 0
    @State private var active = true

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

    private var currencyCode: String { viewModel.metrics?.currencyCode ?? "EUR" }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(.shopwareBlue)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    form
                }
            }
            .background(Color.appBackground)
            .navigationTitle("Edit product")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || isLoading)
                }
            }
        }
        .task { await load() }
        .onChange(of: pickedItem) { item in
            Task { await uploadPicked(item) }
        }
    }

    private var form: some View {
        Form {
            if let errorMessage {
                Section { ErrorBanner(message: errorMessage) }
            }

            Section {
                if images.isEmpty {
                    Text("No images yet.")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondaryText)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(images) { image in
                                galleryCell(image)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                PhotosPicker(selection: $pickedItem, matching: .images) {
                    Label("Add image", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .disabled(imageBusy)
            } header: {
                HStack {
                    Text("Images")
                    if imageBusy {
                        ProgressView().controlSize(.small)
                    }
                }
            } footer: {
                Text("Tap an image to set it as the cover. Long-press for more.")
            }

            Section("Details") {
                LabeledContent("Product number") {
                    Text(detail?.productNumber ?? "—")
                        .foregroundStyle(Color.secondaryText)
                }
                TextField("Name", text: $name)
                Stepper("Stock: \(stock)", value: $stock, in: 0...1_000_000)
                Toggle("Active", isOn: $active)
                    .tint(.shopwareBlue)
            }

            Section {
                HStack {
                    Text("Price (gross)")
                    Spacer()
                    TextField("0.00", text: $priceText)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 130)
                        .decimalKeyboard()
                    Text(currencyCode)
                        .foregroundStyle(Color.secondaryText)
                }
                HStack {
                    Text("Price (net)")
                    Spacer()
                    Text(netDisplay)
                        .foregroundStyle(Color.secondaryText)
                    Text(currencyCode)
                        .foregroundStyle(Color.secondaryText)
                }
            } header: {
                Text("Price")
            } footer: {
                if let rate = detail?.taxRate {
                    Text("Net is derived from gross at \(rate.formatted())% tax.")
                }
            }
        }
        .scrollContentBackground(.hidden)
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
            ProductThumbnail(url: image.url, size: 80)
                .overlay(alignment: .bottom) {
                    if isCover {
                        Text("Cover")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Color.inverseText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.shopwareBlue)
                            .clipShape(Capsule())
                            .padding(.bottom, 5)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isCover ? Color.shopwareBlue : Color.clear, lineWidth: 2)
                )
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
            let newName = trimmedName != detail.name && !trimmedName.isEmpty ? trimmedName : nil
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
