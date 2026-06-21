//
//  ShopwareAPIError.swift
//  ShopwareApp
//
//  Error type for Admin API failures plus helpers that turn raw
//  network/URL errors into actionable, user-facing guidance.
//

import Foundation

enum ShopwareAPIError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let m) = self { return m }
        return nil
    }
}

extension Error {
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let urlError = self as? URLError {
            return urlError.code == .cancelled
        }
        let nsError = self as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    var shopwareDisplayMessage: String {
        if let urlError = self as? URLError {
            return urlError.shopwareDisplayMessage
        }
        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain {
            return URLError(URLError.Code(rawValue: nsError.code)).shopwareDisplayMessage
        }
        return (self as? LocalizedError)?.errorDescription ?? localizedDescription
    }
}

extension URLError {
    var shopwareDisplayMessage: String {
        let failingURL = (self as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL
        let target = failingURL.map { "\nURL: \($0.absoluteString)" } ?? ""

        switch code {
        case .appTransportSecurityRequiresSecureConnection:
            return "iOS blocked this connection because the shop is not using a valid HTTPS connection. Use an HTTPS Shopware URL with a trusted certificate.\(target)"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return "iOS could not trust the shop's SSL certificate. This often works in the simulator if the certificate is trusted on the Mac, but fails on a real iPhone. Install a valid public HTTPS certificate for the shop.\(target)"
        case .cannotFindHost, .dnsLookupFailed:
            return "The iPhone could not find this shop domain. Check the domain, DNS, VPN, and whether the phone is on the same network as the shop.\(target)"
        case .cannotConnectToHost, .networkConnectionLost, .timedOut:
            return "The iPhone could not reach the shop server. If this is a local/dev shop, the phone must use the Mac's LAN IP or a public tunnel, not localhost. Also check firewall, VPN, and hosting/WAF rules.\(target)"
        case .notConnectedToInternet:
            return "The iPhone is not connected to the internet or iOS is blocking network access for this connection.\(target)"
        default:
            return "\(localizedDescription)\(target)"
        }
    }
}
