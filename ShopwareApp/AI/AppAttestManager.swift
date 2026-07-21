//
//  AppAttestManager.swift
//  ShopwareApp
//
//  Binds paid proxy calls to a genuine app installation. The server supplies
//  every challenge and consumes it once; assertions cover the exact chat body.
//

import CryptoKit
import DeviceCheck
import Foundation

@MainActor
final class AppAttestManager {
    static let shared = AppAttestManager()

    struct Headers {
        let keyID: String
        let challenge: String
        let assertion: String
    }

    private struct ChallengeRequest: Encodable {
        let clientID: String
        let purpose: String
        let keyID: String?

        enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case purpose
            case keyID = "key_id"
        }
    }

    private struct ChallengeResponse: Decodable {
        let challenge: String?
        let keyRegistered: Bool?

        enum CodingKeys: String, CodingKey {
            case challenge
            case keyRegistered = "key_registered"
        }
    }

    private struct RegistrationRequest: Encodable {
        let clientID: String
        let keyID: String
        let challenge: String
        let attestation: String

        enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case keyID = "key_id"
            case challenge, attestation
        }
    }

    private struct RegistrationResponse: Decodable {
        let registered: Bool
    }

    private struct ProxyError: Decodable {
        struct Detail: Decodable { let message: String }
        let error: Detail
    }

    private let service = DCAppAttestService.shared
    private let storedKeyID = "aiProxyAppAttestKeyID"

    private init() {}

    func headers(
        baseURL: URL,
        body: Data,
        entitlementJWS: String,
        clientID: String,
        session: URLSession
    ) async throws -> Headers {
        guard service.isSupported else {
            throw ShopwareAPIError.message(
                "Secure app verification is not available on this device. You can still use the assistant with your own AI provider key."
            )
        }

        var keyID = UserDefaults.standard.string(forKey: storedKeyID)
        var challenge = try await requestChallenge(
            baseURL: baseURL,
            purpose: "chat",
            keyID: keyID,
            entitlementJWS: entitlementJWS,
            clientID: clientID,
            session: session
        )

        if keyID == nil || challenge.keyRegistered != true {
            keyID = try await registerKey(
                baseURL: baseURL,
                entitlementJWS: entitlementJWS,
                clientID: clientID,
                session: session
            )
            challenge = try await requestChallenge(
                baseURL: baseURL,
                purpose: "chat",
                keyID: keyID,
                entitlementJWS: entitlementJWS,
                clientID: clientID,
                session: session
            )
        }

        guard let keyID, challenge.keyRegistered == true, let challengeValue = challenge.challenge else {
            throw ShopwareAPIError.message("The app could not establish a secure AI session.")
        }
        let payload = Self.assertionPayload(
            method: "POST",
            path: "/v1/chat",
            challenge: challengeValue,
            body: body
        )
        let assertion = try await service.generateAssertion(
            keyID,
            clientDataHash: Data(SHA256.hash(data: payload))
        )
        return Headers(
            keyID: keyID,
            challenge: challengeValue,
            assertion: assertion.base64EncodedString()
        )
    }

    static func assertionPayload(
        method: String,
        path: String,
        challenge: String,
        body: Data
    ) -> Data {
        let bodyHash = Data(SHA256.hash(data: body)).base64URLEncodedString()
        return Data("shopware-ai-app-attest-v1\n\(method.uppercased())\n\(path)\n\(challenge)\n\(bodyHash)".utf8)
    }

    private func registerKey(
        baseURL: URL,
        entitlementJWS: String,
        clientID: String,
        session: URLSession
    ) async throws -> String {
        let challenge = try await requestChallenge(
            baseURL: baseURL,
            purpose: "attestation",
            keyID: nil,
            entitlementJWS: entitlementJWS,
            clientID: clientID,
            session: session
        )
        guard let challengeValue = challenge.challenge else {
            throw ShopwareAPIError.message("The AI service did not provide an app-verification challenge.")
        }
        let keyID = try await service.generateKey()
        let attestation = try await service.attestKey(
            keyID,
            clientDataHash: Data(SHA256.hash(data: Data(challengeValue.utf8)))
        )
        let response: RegistrationResponse = try await send(
            RegistrationRequest(
                clientID: clientID,
                keyID: keyID,
                challenge: challengeValue,
                attestation: attestation.base64EncodedString()
            ),
            path: "/v1/app-attest/register",
            baseURL: baseURL,
            entitlementJWS: entitlementJWS,
            session: session
        )
        guard response.registered else {
            throw ShopwareAPIError.message("The app could not be verified securely.")
        }
        UserDefaults.standard.set(keyID, forKey: storedKeyID)
        return keyID
    }

    private func requestChallenge(
        baseURL: URL,
        purpose: String,
        keyID: String?,
        entitlementJWS: String,
        clientID: String,
        session: URLSession
    ) async throws -> ChallengeResponse {
        try await send(
            ChallengeRequest(clientID: clientID, purpose: purpose, keyID: keyID),
            path: "/v1/app-attest/challenge",
            baseURL: baseURL,
            entitlementJWS: entitlementJWS,
            session: session
        )
    }

    private func send<RequestBody: Encodable, ResponseBody: Decodable>(
        _ body: RequestBody,
        path: String,
        baseURL: URL,
        entitlementJWS: String,
        session: URLSession
    ) async throws -> ResponseBody {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(entitlementJWS, forHTTPHeaderField: "X-App-Transaction")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            if let error = try? JSONDecoder().decode(ProxyError.self, from: data) {
                throw ShopwareAPIError.message(error.error.message)
            }
            throw ShopwareAPIError.message("The app-verification service returned an error (\(status)).")
        }
        do {
            return try JSONDecoder().decode(ResponseBody.self, from: data)
        } catch {
            throw ShopwareAPIError.message("The app-verification service returned an invalid response.")
        }
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
