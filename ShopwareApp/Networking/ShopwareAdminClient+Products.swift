//
//  ShopwareAdminClient+Products.swift
//  ShopwareApp
//
//  Product search, detail, media gallery, and updates.
//

import Foundation

extension ShopwareAdminClient {
    /// Search products by name or product number. An empty `term` returns the
    /// most recently updated products so the list is populated before typing.
    func searchProducts(term: String, salesChannelID: String?, limit: Int = 50) async throws -> [ProductSummary] {
        var filters: [[String: Any]] = []
        if let salesChannelID {
            filters.append(["type": "equals", "field": "visibilities.salesChannelId", "value": salesChannelID])
        }

        var body: [String: Any] = [
            "limit": limit,
            "filter": filters,
            "associations": ["cover": ["associations": ["media": [:]]]]
        ]
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            body["sort"] = [["field": "updatedAt", "order": "DESC"]]
        } else {
            body["term"] = trimmed
        }

        let response = try await requestJSON(path: "/api/search/product", method: "POST", body: body)
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let attrs = entityAttributes(of: row)
            let name = translatedName(from: attrs) ?? attrs["name"] as? String ?? AppLocalization.string("Unnamed product")
            return ProductSummary(
                id: id,
                name: name,
                productNumber: attrs["productNumber"] as? String ?? "",
                stock: attrs["stock"] as? Int ?? 0,
                active: attrs["active"] as? Bool ?? false,
                price: grossPrice(from: attrs["price"]),
                coverURL: coverURL(from: attrs)
            )
        }
    }

    /// Load a single product's full editable state for the edit sheet.
    /// `languageID` selects which translation of the name is returned.
    func fetchProductDetail(id: String, languageID: String? = nil) async throws -> ProductDetail {
        let response = try await requestJSON(path: "/api/search/product", method: "POST", body: [
            "limit": 1,
            "filter": [["type": "equals", "field": "id", "value": id]],
            "associations": [
                "cover": ["associations": ["media": [:]]],
                "tax": [:]
            ]
        ], languageID: languageID)
        guard let row = (response["data"] as? [[String: Any]])?.first else {
            throw ShopwareAPIError.message("Product not found.")
        }
        let attrs = entityAttributes(of: row)
        let firstPrice = (attrs["price"] as? [[String: Any]])?.first
        let taxRate = (attrs["tax"] as? [String: Any])?["taxRate"].map { decimal(from: $0) }
        return ProductDetail(
            id: id,
            name: translatedName(from: attrs) ?? attrs["name"] as? String ?? "",
            productNumber: attrs["productNumber"] as? String ?? "",
            stock: attrs["stock"] as? Int ?? 0,
            active: attrs["active"] as? Bool ?? false,
            grossPrice: firstPrice?["gross"].map { decimal(from: $0) },
            netPrice: firstPrice?["net"].map { decimal(from: $0) },
            currencyID: firstPrice?["currencyId"] as? String,
            taxRate: taxRate,
            coverURL: coverURL(from: attrs),
            coverID: attrs["coverId"] as? String
        )
    }

    /// Load every image attached to a product (its `product_media` rows),
    /// ordered by position, for the gallery in the edit sheet.
    func fetchProductImages(productID: String) async throws -> [ProductImage] {
        let response = try await requestJSON(path: "/api/search/product-media", method: "POST", body: [
            "filter": [["type": "equals", "field": "productId", "value": productID]],
            "sort": [["field": "position", "order": "ASC"]],
            "associations": ["media": [:]]
        ])
        return (response["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            let attrs = entityAttributes(of: row)
            guard let mediaID = attrs["mediaId"] as? String else { return nil }
            let media = attrs["media"] as? [String: Any]
            return ProductImage(
                id: id,
                mediaID: mediaID,
                url: (media?["url"] as? String).flatMap(URL.init(string:)),
                position: attrs["position"] as? Int ?? 0
            )
        }
    }

    /// Mark an existing product_media row as the product's cover.
    func setProductCover(productID: String, productMediaID: String) async throws {
        _ = try await requestJSON(path: "/api/product/\(productID)", method: "PATCH", body: [
            "coverId": productMediaID
        ])
    }

    /// Remove an image from a product by deleting its product_media row.
    func deleteProductImage(productMediaID: String) async throws {
        _ = try await requestJSON(path: "/api/product-media/\(productMediaID)", method: "DELETE")
    }

    /// Persist a new gallery order by writing each row's position via sync.
    func reorderProductImages(orderedIDs: [String]) async throws {
        let payload = orderedIDs.enumerated().map { index, id in
            ["id": id, "position": index]
        }
        _ = try await requestJSON(path: "/api/_action/sync", method: "POST", body: [
            "reorder-product-media": [
                "entity": "product_media",
                "action": "upsert",
                "payload": payload
            ]
        ])
    }

    /// Patch a product's scalar fields. Only non-nil arguments are written.
    /// Writing a price requires `currencyID` so the price object stays valid.
    /// `languageID` selects which translation the `name` is written into.
    func updateProduct(
        id: String,
        name: String? = nil,
        stock: Int? = nil,
        grossPrice: Decimal? = nil,
        taxRate: Decimal? = nil,
        currencyID: String? = nil,
        active: Bool? = nil,
        languageID: String? = nil
    ) async throws {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let stock { body["stock"] = stock }
        if let active { body["active"] = active }
        if let grossPrice, let currencyID {
            // Net is derived from gross and the tax rate, mirroring the admin's
            // linked price fields (net = gross / (1 + taxRate/100)).
            let net = netFromGross(grossPrice, taxRate: taxRate)
            body["price"] = [[
                "currencyId": currencyID,
                "gross": NSDecimalNumber(decimal: grossPrice).doubleValue,
                "net": NSDecimalNumber(decimal: net).doubleValue,
                "linked": true
            ]]
        }
        guard !body.isEmpty else { return }
        _ = try await requestJSON(path: "/api/product/\(id)", method: "PATCH", body: body, languageID: languageID)
    }

    /// Upload an image and append it to a product's gallery (without disturbing
    /// existing images). Optionally marks the new image as the cover. Returns
    /// the new product_media id.
    ///
    /// `imageData` is inspected for its real format (PhotosPicker often returns
    /// HEIC/PNG, not JPEG), since Shopware keys the upload off the extension and
    /// content type.
    @discardableResult
    func addProductImage(productID: String, imageData: Data, position: Int, setAsCover: Bool) async throws -> String {
        let mediaID = randomEntityID()
        let (ext, contentType) = imageFormat(of: imageData)

        // 1. Create the media entity with a known id so we can target the upload.
        do {
            _ = try await requestJSON(path: "/api/media", method: "POST", body: ["id": mediaID])
        } catch {
            throw ShopwareAPIError.message("Couldn't create the media entry: \(error.shopwareDisplayMessage)")
        }

        // 2. Upload the raw image bytes. Shopware treats any non-JSON
        //    Content-Type as a binary file upload.
        let fileName = "product-\(productID)-\(Int(Date().timeIntervalSince1970))"
        do {
            _ = try await requestRaw(
                path: "/api/_action/media/\(mediaID)/upload",
                method: "POST",
                body: imageData,
                contentType: contentType,
                queryItems: [
                    URLQueryItem(name: "extension", value: ext),
                    URLQueryItem(name: "fileName", value: fileName)
                ]
            )
        } catch {
            throw ShopwareAPIError.message("Couldn't upload the image: \(error.shopwareDisplayMessage)")
        }

        // 3. Create a product_media row linking the media to the product. This is
        //    additive — unlike PATCHing product.media, it doesn't replace the set.
        let productMediaID = randomEntityID()
        do {
            _ = try await requestJSON(path: "/api/product-media", method: "POST", body: [
                "id": productMediaID,
                "productId": productID,
                "mediaId": mediaID,
                "position": position
            ])
        } catch {
            throw ShopwareAPIError.message("Couldn't attach the image: \(error.shopwareDisplayMessage)")
        }

        // 4. Optionally make it the cover.
        if setAsCover {
            try await setProductCover(productID: productID, productMediaID: productMediaID)
        }
        return productMediaID
    }

    /// Pulls the first gross value out of a product's `price` array
    /// ([{ currencyId, gross, net, ... }]).
    private func grossPrice(from value: Any?) -> Decimal? {
        guard let prices = value as? [[String: Any]], let first = prices.first else { return nil }
        return first["gross"].map { decimal(from: $0) }
    }

    /// Reads the cover image URL from a product's `cover.media` association.
    private func coverURL(from attrs: [String: Any]) -> URL? {
        guard let cover = attrs["cover"] as? [String: Any],
              let media = cover["media"] as? [String: Any],
              let urlString = media["url"] as? String else { return nil }
        return URL(string: urlString)
    }

    /// Sniffs an image's format from its magic bytes, returning the file
    /// extension and MIME type Shopware should be told about.
    private func imageFormat(of data: Data) -> (ext: String, contentType: String) {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return ("jpg", "image/jpeg")
        }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return ("png", "image/png")
        }
        if bytes.count >= 12, Array(bytes[4..<8]) == [0x66, 0x74, 0x79, 0x70] {
            // ....ftyp.... → HEIF/HEIC container
            return ("heic", "image/heic")
        }
        if bytes.starts(with: [0x47, 0x49, 0x46]) {
            return ("gif", "image/gif")
        }
        if bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) {
            return ("webp", "image/webp")
        }
        return ("jpg", "image/jpeg")
    }

    private func randomEntityID() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}
