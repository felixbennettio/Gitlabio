import Foundation

/// Sends one prepared request. The live implementation is `URLSessionTransport`;
/// tests and the in-app demo use `DemoTransport`.
public protocol GitLabTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession-backed transport that never follows redirects (so the token header is never
/// forwarded to another location) and validates TLS with the account's `TrustPolicy`.
public final class URLSessionTransport: GitLabTransport {
    private let session: URLSession
    private let delegate: Delegate

    public init(trust: TrustPolicy = .system, configuration: URLSessionConfiguration = .ephemeral) {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        delegate = Delegate(trust: trust)
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    deinit { session.invalidateAndCancel() }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let host = request.url?.host ?? ""
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GitLabError.malformedResponse }
            return (data, http)
        } catch let error as URLError {
            if error.code == .cancelled, delegate.rejectedHosts.contains(host) {
                throw GitLabError.untrustedCertificate(host: host)
            }
            if error.code == .cancelled { throw CancellationError() }
            throw GitLabError.from(urlError: error, host: host)
        }
    }

    final class Delegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        let trust: TrustPolicy
        private let lock = NSLock()
        private var rejected: Set<String> = []
        init(trust: TrustPolicy) { self.trust = trust }

        var rejectedHosts: Set<String> { lock.withLock { rejected } }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? {
            nil
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didReceive challenge: URLAuthenticationChallenge) async
            -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            let space = challenge.protectionSpace
            guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let serverTrust = space.serverTrust else { return (.performDefaultHandling, nil) }
            if case .system = trust { return (.performDefaultHandling, nil) }
            if trust.evaluate(serverTrust, host: space.host) {
                return (.useCredential, URLCredential(trust: serverTrust))
            }
            lock.withLock { _ = rejected.insert(space.host) }
            return (.cancelAuthenticationChallenge, nil)
        }
    }
}

/// Connects once to read the server's certificate chain, so the user can review a
/// self-signed or private-CA certificate before trusting it. Sends no credentials.
public enum CertificateProbe {
    public struct Result: Sendable {
        public let chain: [CertificateSummary]
        public let trustedBySystem: Bool
    }

    public static func inspect(_ instance: GitLabInstance) async throws -> Result {
        let delegate = ProbeDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: instance.endpoint(["version"]))
        request.timeoutInterval = 15
        _ = try? await session.data(for: request)
        guard let result = delegate.result else { throw GitLabError.timedOut }
        return result
    }

    private final class ProbeDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Result?
        var result: Result? { lock.withLock { stored } }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        didReceive challenge: URLAuthenticationChallenge) async
            -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust else { return (.performDefaultHandling, nil) }
            let value = Result(chain: CertificateSummary.chain(of: trust),
                               trustedBySystem: SecTrustEvaluateWithError(trust, nil))
            lock.withLock { stored = value }
            return (.cancelAuthenticationChallenge, nil)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }
}
