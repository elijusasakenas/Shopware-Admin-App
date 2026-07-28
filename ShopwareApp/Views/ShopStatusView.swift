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
        .background(Color.industryBackground)
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("SHOP STATUS & LOG")
                    .industryKicker(11)
                    .foregroundStyle(Color.industryText)
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
                    Text("Shopware version").industryKicker().foregroundStyle(Color.industryFaint)
                    Spacer()
                    Text("Up to date").industryKicker().foregroundStyle(Color.industryAccent)
                }
                Text(version.isEmpty ? "—" : version)
                    .font(IndustryFont.display(34))
                    .foregroundStyle(Color.industryText)
                Rectangle().fill(Color.industryHair).frame(height: 1)
                HStack(spacing: 0) {
                    statusCell("Storefront", value: averageResponse)
                    Rectangle().fill(Color.industryHair).frame(width: 1, height: 40)
                    statusCell("Admin API", value: "LIVE")
                    Rectangle().fill(Color.industryHair).frame(width: 1, height: 40)
                    statusCell("Errors · 24h", value: errorCount.formatted())
                }
            }
        }
        .opacity(isLoading ? 0.45 : 1)
    }

    private func statusCell(_ label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).industryKicker(8.5).foregroundStyle(Color.industryFaint)
            Text(value).font(IndustryFont.display(20)).foregroundStyle(Color.industryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    private var averageResponse: String {
        let responses = domains.compactMap(\.responseMs)
        guard !responses.isEmpty else { return "—" }
        return "\(responses.reduce(0, +) / responses.count) ms"
    }

    private var errorCount: Int {
        logEntries.filter { $0.level >= 400 }.count
    }

    private var domainSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Storefront availability")
                .padding(.bottom, 10)
            Rectangle().fill(Color.industryLine).frame(height: 1)
            if domains.isEmpty {
                emptyRow("NO STOREFRONT DOMAINS")
            } else {
                ForEach(domains) { domain in
                    HStack(spacing: 10) {
                        SeverityLadder(level: domainSeverity(domain))
                        Text(domain.url)
                            .font(IndustryFont.body(13.5))
                            .foregroundStyle(Color.industryText)
                            .lineLimit(1)
                        Spacer()
                        Text(domain.responseMs.map { "\($0) ms" } ?? "—")
                            .font(IndustryFont.display(15))
                            .foregroundStyle(Color.industryDim)
                        Text(domain.statusCode.map(String.init) ?? "—")
                            .industryKicker()
                            .foregroundStyle(Color.industryFaint)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .padding(.vertical, 11)
                    Rectangle().fill(Color.industryHair).frame(height: 1)
                }
            }
        }
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Shop log", detail: "NEWEST FIRST")
                .padding(.bottom, 10)
            Rectangle().fill(Color.industryLine).frame(height: 1)
            if logEntries.isEmpty {
                emptyRow("THE LOG IS EMPTY")
            } else {
                ForEach(logEntries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            SeverityLadder(level: logSeverity(entry))
                            Text(entry.levelLabel).industryKicker().foregroundStyle(Color.industryDim)
                            Spacer()
                            if let createdAt = entry.createdAt {
                                Text(
                                    createdAt.formatted(
                                        Date.FormatStyle(date: .abbreviated, time: .shortened)
                                            .locale(AppLocalization.locale)
                                    )
                                )
                                    .industryKicker(9)
                                    .foregroundStyle(Color.industryFaint)
                            }
                        }
                        Text(entry.message)
                            .font(IndustryFont.body(13))
                            .foregroundStyle(Color.industryDim)
                            .lineSpacing(3)
                            .lineLimit(3)
                    }
                    .padding(.vertical, 10)
                    Rectangle().fill(Color.industryHair).frame(height: 1)
                }
            }
        }
    }

    private func domainSeverity(_ domain: DomainStatus) -> Int {
        guard domain.isHealthy else { return 1 }
        return (domain.responseMs ?? 0) > 400 ? 2 : 3
    }

    private func logSeverity(_ entry: LogEntry) -> Int {
        entry.level >= 400 ? 3 : entry.level >= 300 ? 2 : 1
    }

    private func emptyRow(_ label: LocalizedStringKey) -> some View {
        Text(label)
            .industryKicker()
            .foregroundStyle(Color.industryFaint)
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
