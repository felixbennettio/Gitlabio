import Foundation

/// A GitLab server root, e.g. `https://gitlab.com` or `https://git.example.com/gitlab`.
/// Only HTTPS is accepted, and URLs carrying credentials, queries or fragments are rejected
/// so a token can never leak through the address itself.
public struct GitLabInstance: Hashable, Sendable, Codable {
    public let url: URL

    public static let gitlabCom = try! GitLabInstance("https://gitlab.com")

    public init(_ value: String) throws {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "https://" + text }
        guard var parts = URLComponents(string: text),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              !parts.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw GitLabError.invalidInstance
        }
        parts.scheme = "https"
        parts.host = host.lowercased()
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        // Users often paste the API root; normalise it back to the server root.
        if parts.path.hasSuffix("/api/v4") { parts.path.removeLast("/api/v4".count) }
        guard let url = parts.url else { throw GitLabError.invalidInstance }
        self.url = url
    }

    public var host: String { url.host ?? "" }

    /// Display form without the scheme, e.g. `git.example.com/gitlab`.
    public var displayName: String {
        var text = url.absoluteString
        if text.hasPrefix("https://") { text.removeFirst("https://".count) }
        return text
    }

    public var isGitLabCom: Bool { host == "gitlab.com" }

    /// Builds `<root>/api/v4/<segments>`; every segment is encoded independently, so
    /// `group/project` and nested file paths stay single path components.
    public func endpoint(_ segments: [String], query: [URLQueryItem] = []) -> URL {
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        parts.percentEncodedPath += "/api/v4/" + segments.map {
            $0.addingPercentEncoding(withAllowedCharacters: allowed)!
        }.joined(separator: "/")
        if !query.isEmpty {
            parts.percentEncodedQuery = query.map { item in
                let name = item.name.addingPercentEncoding(withAllowedCharacters: allowed)!
                guard let value = item.value else { return name }
                return name + "=" + value.addingPercentEncoding(withAllowedCharacters: allowed)!
            }.joined(separator: "&")
        }
        return parts.url!
    }

    /// `<root>/api/graphql`.
    public var graphQLEndpoint: URL { url.appendingPathComponent("api").appendingPathComponent("graphql") }

    /// Resolves a server-relative path such as an avatar `/uploads/...` against the root.
    public func resolve(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
        return URL(string: url.absoluteString + (path.hasPrefix("/") ? path : "/" + path))
    }
}
