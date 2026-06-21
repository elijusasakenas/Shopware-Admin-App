//
//  ShopStatusView.swift
//  ShopwareApp
//
//  Shop health: Shopware version, storefront reachability with response
//  times, and recent log entries.
//

import SwiftUI

struct ShopStatusView: View {
    @ObservedObject var viewModel: ShopwareDashboardViewModel

    @State private var version = ""
    @State private var domains: [DomainStatus] = []
    @State private var logEntries: [LogEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let errorMessage { ErrorBanner(message: errorMessage) }

                if isLoading {
                    ProgressView().tint(.shopwareBlue).frame(maxWidth: .infinity).padding(40)
                } else {
                    // Version
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Shopware version")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.secondaryText)
                                .textCase(.uppercase)
                            Text(version)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.primaryText)
                        }
                        Spacer()
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title2)
                            .foregroundStyle(Color.shopwareBlue)
                    }
                    .padding(16)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))

                    // Storefront reachability
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Storefront availability")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.primaryText)

                        if domains.isEmpty {
                            Text("No storefront domains configured.")
                                .font(.subheadline)
                                .foregroundStyle(Color.secondaryText)
                        } else {
                            ForEach(domains) { domain in
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(domain.isHealthy ? Color.green : Color.red)
                                        .frame(width: 10, height: 10)
                                    Text(domain.url)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.primaryText)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                    Spacer()
                                    if let ms = domain.responseMs {
                                        Text("\(ms) ms")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(Color.secondaryText)
                                    }
                                    Text(domain.statusCode.map(String.init) ?? "—")
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background((domain.isHealthy ? Color.green : Color.red).opacity(0.12))
                                        .foregroundStyle(domain.isHealthy ? Color.green : Color.red)
                                        .clipShape(Capsule())
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))

                    // Shop log
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Shop log")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.primaryText)

                        if logEntries.isEmpty {
                            Text("The log is empty.")
                                .font(.subheadline)
                                .foregroundStyle(Color.secondaryText)
                        } else {
                            ForEach(logEntries) { entry in
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(entry.levelLabel)
                                            .font(.caption2.weight(.bold))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(entry.levelColor.opacity(0.12))
                                            .foregroundStyle(entry.levelColor)
                                            .clipShape(Capsule())
                                        Spacer()
                                        if let createdAt = entry.createdAt {
                                            Text(createdAt.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption2)
                                                .foregroundStyle(Color.secondaryText)
                                        }
                                    }
                                    Text(entry.message)
                                        .font(.caption)
                                        .foregroundStyle(Color.primaryText)
                                        .lineLimit(3)
                                }
                                .padding(.vertical, 6)
                                if entry.id != logEntries.last?.id { Divider() }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.border, lineWidth: 1))
                }
            }
            .padding(20)
        }
        .background(Color.appBackground)
        .navigationTitle("Shop status")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private func load() async {
        do {
            version = (try? await viewModel.shopwareVersion()) ?? "Unknown"
            logEntries = (try? await viewModel.logEntries()) ?? []
            let urls = try await viewModel.domainURLs()
            var results: [DomainStatus] = []
            for url in urls {
                results.append(await checkDomain(url))
            }
            domains = results
        } catch {
            errorMessage = error.shopwareDisplayMessage
        }
        isLoading = false
    }

    private func checkDomain(_ urlString: String) async -> DomainStatus {
        guard let url = URL(string: urlString) else {
            return DomainStatus(url: urlString, statusCode: nil, responseMs: nil)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let start = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            return DomainStatus(url: urlString, statusCode: (response as? HTTPURLResponse)?.statusCode, responseMs: ms)
        } catch {
            return DomainStatus(url: urlString, statusCode: nil, responseMs: nil)
        }
    }
}
