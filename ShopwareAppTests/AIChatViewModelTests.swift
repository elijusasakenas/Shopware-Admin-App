import XCTest
@testable import ShopwareApp

@MainActor
final class AIChatViewModelTests: XCTestCase {
    private var service: FakeAIChatService!

    override func tearDown() {
        service = nil
        MockURLProtocol.reset()
        super.tearDown()
    }

    func testPauseTurnContinuesUntilEndTurn() async {
        let viewModel = makeViewModel()
        service.enqueue(text: "Looking it up.", stopReason: "pause_turn")
        service.enqueue(text: "Stock is 12.", stopReason: "end_turn")

        viewModel.send("How much stock?")
        await waitUntil("the conversation finishes") { !viewModel.isThinking }

        XCTAssertEqual(service.sendCount, 2)
        XCTAssertEqual(viewModel.entries.map(\.kind), [
            .user("How much stock?"),
            .assistant("Looking it up."),
            .assistant("Stock is 12."),
        ])
        XCTAssertNil(viewModel.pendingApproval)
        XCTAssertTrue(viewModel.canSend)
    }

    func testWriteApprovalPausesUntilNativeConfirm() async {
        let viewModel = makeViewModel()
        let approval = makeApproval(token: "approval-token", expiresAt: futureMillis())
        service.enqueue(
            content: [
                .text("Ready to update stock."),
                .other(.object([
                    "type": .string("mcp_tool_use"),
                    "id": .string("call_1"),
                    "name": .string("product-update"),
                ])),
            ],
            stopReason: "pause_turn",
            approval: approval
        )
        service.enqueue(text: "Updated.", stopReason: "end_turn")

        viewModel.send("Set stock to 4")
        await waitUntil("approval is pending") { viewModel.pendingApproval != nil }

        XCTAssertEqual(service.sendCount, 1)
        XCTAssertFalse(viewModel.canSend)
        XCTAssertEqual(viewModel.pendingApproval?.token, "approval-token")
        XCTAssertTrue(viewModel.entries.map(\.kind).contains(.toolActivity(label: "product update", failed: false)))

        viewModel.approvePendingChange()
        await waitUntil("the approved retry finishes") { !viewModel.isThinking }

        XCTAssertEqual(service.sendCount, 2)
        XCTAssertEqual(service.lastApprovalToken, "approval-token")
        XCTAssertNil(viewModel.pendingApproval)
        XCTAssertTrue(viewModel.entries.map(\.kind).contains(.assistant("Updated.")))
    }

    func testExpiredApprovalDoesNotResume() async {
        let viewModel = makeViewModel()
        service.enqueue(
            text: "Need approval.",
            stopReason: "end_turn",
            approval: makeApproval(token: "stale", expiresAt: 1)
        )

        viewModel.send("Delete the product")
        await waitUntil("approval is pending") { viewModel.pendingApproval != nil }

        viewModel.approvePendingChange()

        XCTAssertEqual(service.sendCount, 1)
        XCTAssertNil(viewModel.pendingApproval)
        XCTAssertFalse(viewModel.isThinking)
        XCTAssertEqual(
            viewModel.entries.last?.kind,
            .error(AppLocalization.string("The approval expired. Ask the assistant to prepare the change again."))
        )
    }

    func testCancelStopsAnInFlightTurn() async {
        let viewModel = makeViewModel()
        service.hangUntilCancelled = true

        viewModel.send("Hello")
        XCTAssertTrue(viewModel.isThinking)

        viewModel.cancel()
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertFalse(viewModel.isThinking)
        XCTAssertEqual(
            viewModel.entries.map(\.kind),
            [
                .user("Hello"),
                .error(AppLocalization.string("Request cancelled.")),
            ]
        )
        XCTAssertTrue(viewModel.canSend)
    }

    func testTooManyPauseTurnsSurfacesAStepLimit() async {
        let viewModel = makeViewModel()
        for _ in 0..<8 {
            service.enqueue(text: "Still working.", stopReason: "pause_turn")
        }

        viewModel.send("Keep going")
        await waitUntil("the step cap is hit") { !viewModel.isThinking }

        XCTAssertEqual(service.sendCount, 8)
        XCTAssertEqual(
            viewModel.entries.last?.kind,
            .error(AppLocalization.string("The assistant stopped after too many steps. Please refine your request."))
        )
    }

    func testFailedToolResultsMarkTheActivityChip() async {
        let viewModel = makeViewModel()
        service.enqueue(
            content: [
                .other(.object([
                    "type": .string("mcp_tool_use"),
                    "id": .string("call_1"),
                    "name": .string("product-search"),
                ])),
                .other(.object([
                    "type": .string("mcp_tool_result"),
                    "tool_use_id": .string("call_1"),
                    "is_error": .bool(true),
                    "content": .string("blocked"),
                ])),
            ],
            stopReason: "end_turn"
        )

        viewModel.send("Find mugs")
        await waitUntil("the tool chip is recorded") { !viewModel.isThinking }

        XCTAssertEqual(
            viewModel.entries.map(\.kind),
            [
                .user("Find mugs"),
                .toolActivity(label: "product search", failed: true),
            ]
        )
    }

    func testSendErrorIsShownWhenTheProxyFails() async {
        let viewModel = makeViewModel()
        service.enqueueError(ShopwareAPIError.message("The AI service is unavailable."))

        viewModel.send("Hello")
        await waitUntil("the error is shown") { !viewModel.isThinking }

        XCTAssertEqual(
            viewModel.entries.map(\.kind),
            [
                .user("Hello"),
                .error("The AI service is unavailable."),
            ]
        )
    }

    // MARK: - Helpers

    private func makeViewModel() -> AIChatViewModel {
        service = FakeAIChatService()
        return AIChatViewModel(
            client: TestHTTPFactory.client(cachedToken: "shop-token"),
            entitlementProvider: { "test-jws" },
            service: service
        )
    }

    private func makeApproval(token: String, expiresAt: Int64) -> AIApprovalChallenge {
        AIApprovalChallenge(
            token: token,
            actions: [
                AIApprovalChallenge.Action(
                    fingerprint: "fp",
                    tool: "product-update",
                    summary: "product-update: {\"stock\":4}"
                ),
            ],
            expiresAt: expiresAt
        )
    }

    private func futureMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1_000) + 60_000
    }

    private func waitUntil(
        _ description: String,
        timeout: TimeInterval = 2,
        _ predicate: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !predicate() {
            if Date() > deadline {
                XCTFail("Timed out waiting for \(description)")
                return
            }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

@MainActor
private final class FakeAIChatService: AIChatSending {
    var hangUntilCancelled = false
    private(set) var sendCount = 0
    private(set) var lastApprovalToken: String?
    private var queued: [Result<AIChatResponse, Error>] = []

    func enqueue(
        text: String,
        stopReason: String?,
        approval: AIApprovalChallenge? = nil
    ) {
        enqueue(content: [.text(text)], stopReason: stopReason, approval: approval)
    }

    func enqueue(
        content: [AIContentBlock],
        stopReason: String?,
        approval: AIApprovalChallenge? = nil
    ) {
        queued.append(.success(AIChatResponse(
            content: content,
            stopReason: stopReason,
            usage: nil,
            approval: approval
        )))
    }

    func enqueueError(_ error: Error) {
        queued.append(.failure(error))
    }

    func send(
        messages: [AIMessage],
        mcpURL: URL,
        mcpToken: String,
        entitlementJWS: String?,
        credential: AIProviderCredential?,
        approvalToken: String?
    ) async throws -> AIChatResponse {
        sendCount += 1
        lastApprovalToken = approvalToken
        XCTAssertEqual(mcpURL.absoluteString, "https://shop.example.test/api/_mcp")
        XCTAssertEqual(mcpToken, "shop-token")
        XCTAssertEqual(entitlementJWS, "test-jws")
        XCTAssertNil(credential)
        XCTAssertFalse(messages.isEmpty)

        if hangUntilCancelled {
            try await Task.sleep(for: .seconds(30))
        }

        guard !queued.isEmpty else {
            return AIChatResponse(content: [.text("ok")], stopReason: "end_turn", usage: nil, approval: nil)
        }
        return try queued.removeFirst().get()
    }
}
