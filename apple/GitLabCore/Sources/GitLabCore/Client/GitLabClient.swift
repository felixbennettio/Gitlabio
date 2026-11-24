import Foundation

public enum Credential: Sendable, Hashable {
    /// Personal, project or group access token (`PRIVATE-TOKEN` header).
    case accessToken(String)
    /// OAuth 2 access token (`Authorization: Bearer`).
    case oauth(String)
    /// No credentials (public data only).
    case anonymous

    var isValid: Bool {
        switch self {
        case .anonymous: return true
        case .accessToken(let value), .oauth(let value):
            return !value.isEmpty && value.unicodeScalars.allSatisfy { (33...126).contains($0.value) }
        }
    }
}

public struct Page<Element: Sendable>: Sendable {
    public var items: [Element]
    public var next: Int?
    public var total: Int?

    public init(items: [Element], next: Int?, total: Int? = nil) {
        self.items = items
        self.next = next
        self.total = total
    }
}

/// A thin, typed GitLab REST v4 client. Endpoint groups live in `Endpoints/`.
public final class GitLabClient: Sendable {
    public let instance: GitLabInstance
    private let credential: Credential
    private let transport: GitLabTransport
    public static let pageSize = 30

    public init(instance: GitLabInstance, credential: Credential, transport: GitLabTransport) {
        self.instance = instance
        self.credential = credential
        self.transport = transport
    }

    public convenience init(instance: GitLabInstance, token: String, trust: TrustPolicy = .system) {
        self.init(instance: instance, credential: .accessToken(token), transport: URLSessionTransport(trust: trust))
    }

    // MARK: Requests

    public func request(_ segments: [String], query: [URLQueryItem] = [], method: String = "GET",
                        body: Data? = nil) throws -> URLRequest {
        guard credential.isValid else { throw GitLabError.invalidInput("访问令牌包含无效字符。") }
        var request = URLRequest(url: instance.endpoint(segments, query: query))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        authorize(&request)
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func authorize(_ request: inout URLRequest) {
        switch credential {
        case .accessToken(let token): request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
        case .oauth(let token): request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        case .anonymous: break
        }
    }

    /// Runs a GraphQL query for the few things REST does not expose (CI inputs, prefilled variables).
    /// GraphQL keys are camelCase, so the plain decoder is used. Errors become `.validation`.
    func graphQL<T: Decodable>(_ query: String, variables: [String: String] = [:]) async throws -> T {
        guard credential.isValid else { throw GitLabError.invalidInput("访问令牌包含无效字符。") }
        var request = URLRequest(url: instance.graphQLEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        authorize(&request)
        request.httpBody = try JSONEncoder().encode(GraphQLRequest(query: query, variables: variables))
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw GitLabError.from(status: response.statusCode, body: data, headers: response.allHeaderFields)
        }
        let reply: GraphQLResponse<T>
        do { reply = try JSONDecoder().decode(GraphQLResponse<T>.self, from: data) }
        catch { throw GitLabError.malformedResponse }
        if let message = reply.errors?.first?.message {
            throw GitLabError.validation(GitLabError.sanitise(message))
        }
        guard let value = reply.data else { throw GitLabError.malformedResponse }
        return value
    }

    private struct GraphQLRequest: Encodable {
        let query: String
        let variables: [String: String]
    }

    private struct GraphQLResponse<T: Decodable>: Decodable {
        struct Message: Decodable { let message: String }
        let data: T?
        let errors: [Message]?
    }

    @discardableResult
    func data(_ segments: [String], query: [URLQueryItem] = [], method: String = "GET",
              body: Data? = nil) async throws -> (Data, HTTPURLResponse) {
        let request = try request(segments, query: query, method: method, body: body)
        let (data, response) = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else {
            throw GitLabError.from(status: response.statusCode, body: data, headers: response.allHeaderFields)
        }
        return (data, response)
    }

    func get<T: Decodable>(_ segments: [String], query: [URLQueryItem] = []) async throws -> T {
        try JSON.decode(try await data(segments, query: query).0)
    }

    func send<T: Decodable>(_ method: String, _ segments: [String], query: [URLQueryItem] = [],
                            body: some Encodable) async throws -> T {
        try JSON.decode(try await data(segments, query: query, method: method, body: JSON.encode(body)).0)
    }

    func send<T: Decodable>(_ method: String, _ segments: [String], query: [URLQueryItem] = []) async throws -> T {
        try JSON.decode(try await data(segments, query: query, method: method).0)
    }

    func perform(_ method: String, _ segments: [String], query: [URLQueryItem] = [],
                 body: (some Encodable)? = Optional<Empty>.none) async throws {
        try await data(segments, query: query, method: method, body: body.map { try JSON.encode($0) })
    }

    public func list<T: Decodable & Sendable>(_ segments: [String], page: Int = 1, perPage: Int = GitLabClient.pageSize,
                                              query: [URLQueryItem] = []) async throws -> Page<T> {
        let (bytes, response) = try await data(segments, query: query + [
            .init(name: "page", value: String(page)), .init(name: "per_page", value: String(perPage))
        ])
        let next = (response.value(forHTTPHeaderField: "X-Next-Page")).flatMap(Int.init)
        let total = (response.value(forHTTPHeaderField: "X-Total")).flatMap(Int.init)
        return Page(items: try JSON.decode(bytes), next: next.flatMap { $0 > page ? $0 : nil }, total: total)
    }

    struct Empty: Codable {}
}

/// Shared JSON configuration: snake_case keys and GitLab's ISO 8601 timestamps
/// (with or without fractional seconds, or a plain date for due dates).
public enum JSON {
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return decoder
    }()

    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.ISO8601Format(.init(includingFractionalSeconds: true)))
        }
        return encoder
    }()

    public static func parseDate(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601) { return date }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle().year().month().day().dateSeparator(.dash)) {
            return date
        }
        return nil
    }

    static func decode<T: Decodable>(_ data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw GitLabError.malformedResponse }
    }

    static func encode(_ value: some Encodable) throws -> Data { try encoder.encode(value) }

    /// No key conversion: for bodies whose keys are user-defined, such as pipeline input names.
    static func encodeVerbatim(_ value: some Encodable) throws -> Data { try JSONEncoder().encode(value) }
}
