import CryptoKit
import Foundation
import Security

/// How an account validates its server's TLS certificate.
///
/// `system` is the default and uses the platform trust store only. `custom` adds
/// certificates the user explicitly chose for one host: CA certificates become extra
/// anchors (chain and hostname are still validated), and a pinned leaf fingerprint
/// accepts exactly that certificate for that host. There is deliberately no option that
/// disables validation.
public enum TrustPolicy: Codable, Hashable, Sendable {
    case system
    case custom(CustomTrust)

    public struct CustomTrust: Codable, Hashable, Sendable {
        public var host: String
        /// DER-encoded CA certificates added as anchors next to the system store.
        public var anchors: [Data]
        /// Lowercase hex SHA-256 fingerprints of accepted leaf certificates.
        public var pinnedLeafSHA256: [String]

        public init(host: String, anchors: [Data] = [], pinnedLeafSHA256: [String] = []) {
            self.host = host.lowercased()
            self.anchors = anchors
            self.pinnedLeafSHA256 = pinnedLeafSHA256.map { $0.lowercased() }
        }
    }

    public var isCustom: Bool { if case .custom = self { return true } else { return false } }

    /// Evaluates a server trust for `host`. Returns true when the connection may proceed.
    public func evaluate(_ trust: SecTrust, host: String) -> Bool {
        switch self {
        case .system:
            return SecTrustEvaluateWithError(trust, nil)
        case .custom(let custom):
            if SecTrustEvaluateWithError(trust, nil) { return true }
            guard custom.host == host.lowercased() else { return false }
            if !custom.anchors.isEmpty {
                let certificates = custom.anchors.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
                SecTrustSetAnchorCertificates(trust, certificates as CFArray)
                SecTrustSetAnchorCertificatesOnly(trust, false)
                if SecTrustEvaluateWithError(trust, nil) { return true }
            }
            guard let leaf = CertificateSummary.chain(of: trust).first else { return false }
            return custom.pinnedLeafSHA256.contains(leaf.sha256)
        }
    }
}

/// A readable description of one certificate, used to let the user confirm a fingerprint.
public struct CertificateSummary: Hashable, Sendable, Identifiable {
    public var id: String { sha256 }
    public let subject: String
    public let sha256: String
    public let der: Data

    public init(der: Data) {
        self.der = der
        self.sha256 = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
        if let certificate = SecCertificateCreateWithData(nil, der as CFData),
           let summary = SecCertificateCopySubjectSummary(certificate) as String? {
            subject = summary
        } else {
            subject = "未知证书"
        }
    }

    /// `AB:CD:…` grouping for display.
    public var formattedFingerprint: String {
        stride(from: 0, to: sha256.count, by: 2).map { offset -> String in
            let start = sha256.index(sha256.startIndex, offsetBy: offset)
            return String(sha256[start..<sha256.index(start, offsetBy: 2)]).uppercased()
        }.joined(separator: ":")
    }

    public static func chain(of trust: SecTrust) -> [CertificateSummary] {
        let chain = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
        return chain.map { CertificateSummary(der: SecCertificateCopyData($0) as Data) }
    }

    /// Accepts PEM (one or more blocks) or raw DER.
    public static func parse(_ data: Data) -> [CertificateSummary] {
        if let text = String(data: data, encoding: .utf8), text.contains("-----BEGIN CERTIFICATE-----") {
            return text.components(separatedBy: "-----BEGIN CERTIFICATE-----").dropFirst().compactMap { block in
                guard let body = block.components(separatedBy: "-----END CERTIFICATE-----").first else { return nil }
                let base64 = body.filter { !$0.isWhitespace }
                guard let der = Data(base64Encoded: base64),
                      SecCertificateCreateWithData(nil, der as CFData) != nil else { return nil }
                return CertificateSummary(der: der)
            }
        }
        guard SecCertificateCreateWithData(nil, data as CFData) != nil else { return [] }
        return [CertificateSummary(der: data)]
    }
}
