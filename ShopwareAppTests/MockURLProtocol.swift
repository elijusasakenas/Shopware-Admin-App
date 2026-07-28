import Foundation
@testable import ShopwareApp

struct MockHTTPResponse {
    let statusCode: Int
    let headers: [String: String]
    let data: Data

    static func json(
        _ json: String,
        statusCode: Int = 200,
        headers: [String: String] = [:]
    ) -> MockHTTPResponse {
        MockHTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"].merging(headers) { _, new in new },
            data: Data(json.utf8)
        )
    }

    static func empty(statusCode: Int = 204) -> MockHTTPResponse {
        MockHTTPResponse(statusCode: statusCode, headers: [:], data: Data())
    }
}

final class MockURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> MockHTTPResponse

    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var requests: [URLRequest] = []
    private static let lock = NSLock()

    static func install(_ handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        requests = []
        lock.unlock()
    }

    static func reset() {
        lock.lock()
        handler = nil
        requests = []
        lock.unlock()
    }

    static func capturedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let capturedRequest = Self.snapshot(request)

        Self.lock.lock()
        Self.requests.append(capturedRequest)
        let handler = Self.handler
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.resourceUnavailable)
            )
            return
        }

        do {
            let result = try handler(capturedRequest)
            guard let url = capturedRequest.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: result.statusCode,
                    httpVersion: "HTTP/1.1",
                    headerFields: result.headers
                  )
            else {
                throw URLError(.badServerResponse)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if !result.data.isEmpty {
                client?.urlProtocol(self, didLoad: result.data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func snapshot(_ request: URLRequest) -> URLRequest {
        guard request.httpBody == nil, let stream = request.httpBodyStream else {
            return request
        }

        stream.open()
        defer { stream.close() }

        var body = Data()
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            guard count > 0 else { break }
            body.append(buffer, count: count)
        }

        var capturedRequest = request
        capturedRequest.httpBodyStream = nil
        capturedRequest.httpBody = body
        return capturedRequest
    }
}

enum TestHTTPFactory {
    static func client(cachedToken: String? = nil) -> ShopwareAdminClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let connection = ShopwareConnection(
            shopURL: "https://shop.example.test",
            accessKey: " access-key ",
            secretKey: " secret-key "
        )
        let client = ShopwareAdminClient(connection: connection, session: session)
        if let cachedToken {
            client.token = AccessToken(
                value: cachedToken,
                expiresAt: Date().addingTimeInterval(600)
            )
        }
        return client
    }

    static func jsonBody(of request: URLRequest) throws -> [String: Any] {
        guard let data = request.httpBody else { return [:] }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}
