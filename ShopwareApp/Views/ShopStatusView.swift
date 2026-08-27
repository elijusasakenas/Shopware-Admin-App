import SwiftUI

struct ShopStatusView: View {
    @ObservedObject var settings: ShopSettingsViewModel
    @State private var version = ""
    @State private var domains: [DomainStatus] = []
    @State private var logEntries: [LogEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if let errorMessage { ErrorBanner(message: errorMessage) }
                versionPlate
                domainSection
                logSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 32)
        }
        .background(Color.appBackground)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("SHOP STATUS & LOG")
                    .font(.headline)
                    .foregroundStyle(Color.primaryText)
            }
        }
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private var versionPlate: some View {
        BlueprintFrame {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Shopware version").font(.subheadline).foregroundStyle(Color.secondaryText)
                    Spacer()
                    Text(healthLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(healthAccent ? Color.shopwareBlue : Color.secondaryText)
                }
                Text(version.isEmpty ? "—" : version)
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(Color.primaryText)
                Divider()
                HStack(spacing: 0) {
                    statusCell("Storefront", value: averageResponse)
                    Divider().frame(height: 40)
                    statusCell("Admin API", value: adminAPILabel)
                    Divider().frame(height: 40)
                    statusCell("Errors · 24h", value: errorCount.formatted())
                }
            }
        }
        .opacity(isLoading ? 0.45 : 1)
    }

    private func statusCell(_ label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption).foregroundStyle(Color.secondaryText)
            Text(value).font(.headline).foregroundStyle(Color.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private var adminAPILabel: String {
        if isLoading { return "—" }
        if version.isEmpty || version == "Unknown" { return "—" }
        return AppLocalization.string("LIVE")
    }

    private var healthLabel: String {
        if isLoading { return "—" }
        if domains.contains(where: { !$0.isHealthy }) {
            return AppLocalization.string("ISSUES")
        }
        if errorCount > 0 {
            return AppLocalization.string("\(errorCount) ERRORS")
        }
        if domains.contains(where: \.isHealthy) {
            return AppLocalization.string("ALL GREEN")
        }
        if version.isEmpty || version == "Unknown" { return "—" }
        return AppLocalization.string("LIVE")
    }

    private var healthAccent: Bool {
        !isLoading && (domains.contains(where: { !$0.isHealthy }) || errorCount > 0 || domains.contains(where: \.isHealthy))
    }

    private var averageResponse: String {
        let responses = domains.compactMap(\.responseMs)
        guard !responses.isEmpty else { return "—" }
        return "\(responses.reduce(0, +) / responses.count) ms"
    }

    private var errorCount: Int {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return logEntries.filter { entry in
            guard entry.level >= 400, let createdAt = entry.createdAt else { return false }
            return createdAt >= cutoff
        }.count
    }

    private var domainSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Storefront availability")
                .padding(.bottom, 10)
            Divider()
            if domains.isEmpty {
                emptyRow("NO STOREFRONT DOMAINS")
            } else {
                ForEach(domains) { domain in
                    HStack(spacing: 10) {
                        Image(systemName: domain.isHealthy ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(domain.isHealthy ? Color.green : Color.red)
                            .frame(width: 22)
                            .accessibilityLabel(
                                domain.isHealthy ? Text("Available") : Text("Unavailable")
                            )
                        Text(domain.url)
                            .font(.subheadline)
                            .foregroundStyle(Color.primaryText)
                            .lineLimit(1)
                        Spacer()
                        Text(domain.responseMs.map { "\($0) ms" } ?? "—")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.secondaryText)
                        Text(domain.statusCode.map(String.init) ?? "—")
                            .font(.caption)
                            .foregroundStyle(Color.secondaryText)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .padding(.vertical, 11)
                    if domain.id != domains.last?.id {
                        Rectangle().fill(Color.border.opacity(0.55)).frame(height: 1)
                    }
                }
            }
        }
        .shopwareCard()
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Shop log", detail: "NEWEST FIRST")
                .padding(.bottom, 10)
            Divider()
            if logEntries.isEmpty {
                emptyRow("THE LOG IS EMPTY")
            } else {
                ForEach(logEntries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            SeverityLadder(level: logSeverity(entry))
                            Text(entry.levelLabel).font(.caption.weight(.semibold)).foregroundStyle(Color.secondaryText)
                            Spacer()
                            if let createdAt = entry.createdAt {
                                Text(
                                    createdAt.formatted(
                                        Date.FormatStyle(date: .abbreviated, time: .shortened)
                                            .locale(AppLocalization.locale)
                                    )
                                )
                                    .font(.caption2)
                                    .foregroundStyle(Color.secondaryText)
                            }
                        }
                        Text(entry.message)
                            .font(.caption)
                            .foregroundStyle(Color.secondaryText)
                            .lineSpacing(3)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 10)
                    Rectangle().fill(Color.border.opacity(0.55)).frame(height: 1)
                }
            }
        }
        .shopwareCard()
    }

    private func logSeverity(_ entry: LogEntry) -> Int {
        entry.level >= 400 ? 3 : entry.level >= 300 ? 2 : 1
    }

    private func emptyRow(_ label: LocalizedStringKey) -> some View {
        Text(label)
            .font(.subheadline)
            .foregroundStyle(Color.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(22)
    }

    private func load() async {
        do {
            version = (try? await settings.shopwareVersion()) ?? "Unknown"
            logEntries = (try? await settings.logEntries()) ?? []
            let urls = try await settings.domainURLs()
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
            let milliseconds = Int(Date().timeIntervalSince(start) * 1000)
            return DomainStatus(
                url: urlString,
                statusCode: (response as? HTTPURLResponse)?.statusCode,
                responseMs: milliseconds
            )
        } catch {
            return DomainStatus(url: urlString, statusCode: nil, responseMs: nil)
        }
    }
}
