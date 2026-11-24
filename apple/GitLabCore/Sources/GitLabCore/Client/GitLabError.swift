import Foundation

public enum GitLabError: Error, LocalizedError, Equatable, Sendable {
    case invalidInstance
    case invalidInput(String)
    case unauthorized
    case forbidden(String?)
    case notFound
    case conflict(String?)
    case validation(String?)
    case rateLimited(retryAfter: Int?)
    case server(Int)
    case http(Int, String?)
    case untrustedCertificate(host: String)
    case offline
    case timedOut
    case transport(Int)
    case malformedResponse
    case binaryFile
    case fileTooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidInstance:
            return "请输入 HTTPS 实例地址（可带部署子路径），不能包含账户、查询参数或片段。"
        case .invalidInput(let reason): return reason
        case .unauthorized: return "令牌无效或已过期，请在「我」中更新账户凭证。"
        case .forbidden(let message):
            return message.map { "没有权限：\($0)" } ?? "没有权限。请检查你的项目角色、令牌范围和分支保护规则。"
        case .notFound: return "内容不存在，或当前账户无权查看。"
        case .conflict(let message):
            return message.map { "操作冲突：\($0)" } ?? "操作冲突：内容可能已被他人修改，请刷新后重试。"
        case .validation(let message):
            return message.map { "GitLab 拒绝了请求：\($0)" } ?? "GitLab 拒绝了请求，请检查输入。"
        case .rateLimited(let retry):
            return retry.map { "请求过于频繁，请 \($0) 秒后再试。" } ?? "请求过于频繁，请稍后再试。"
        case .server(let status): return "GitLab 服务器出错（HTTP \(status)），请稍后再试。"
        case .http(let status, let message):
            return message.map { "请求失败（HTTP \(status)）：\($0)" } ?? "请求失败（HTTP \(status)）。"
        case .untrustedCertificate(let host):
            return "\(host) 的证书不受信任。若这是你的自建实例，可在账户设置中核对指纹后信任该证书。"
        case .offline: return "网络不可用，请检查网络连接。"
        case .timedOut: return "连接超时，请检查实例地址和网络。"
        case .transport(let code): return "网络请求失败（错误 \(code)）。"
        case .malformedResponse: return "服务器返回了无法识别的数据。确认地址指向 GitLab 实例。"
        case .binaryFile: return "这不是可编辑的 UTF-8 文本文件。"
        case .fileTooLarge: return "文件超过 1 MiB，无法在应用内编辑。"
        }
    }

    public var isAuthenticationFailure: Bool { self == .unauthorized }

    /// Maps an HTTP status and response body to a typed error. The server message is
    /// shortened and stripped of control characters before it can reach the UI.
    static func from(status: Int, body: Data, headers: [AnyHashable: Any]) -> GitLabError {
        let message = serverMessage(body)
        switch status {
        case 401: return .unauthorized
        case 403: return .forbidden(message)
        case 404: return .notFound
        case 409: return .conflict(message)
        case 400, 405, 406, 412, 422: return .validation(message)
        case 429:
            let retry = (headers["Retry-After"] as? String).flatMap(Int.init)
            return .rateLimited(retryAfter: retry)
        case 500...599: return .server(status)
        default: return .http(status, message)
        }
    }

    static func from(urlError: URLError, host: String) -> GitLabError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: return .offline
        case .timedOut: return .timedOut
        case .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid, .secureConnectionFailed:
            return .untrustedCertificate(host: host)
        default: return .transport(urlError.code.rawValue)
        }
    }

    static func serverMessage(_ body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        var parts: [String] = []
        func collect(_ value: Any, prefix: String?) {
            if let text = value as? String {
                parts.append(prefix.map { "\($0) \(text)" } ?? text)
            } else if let list = value as? [Any] {
                list.forEach { collect($0, prefix: prefix) }
            } else if let map = value as? [String: Any] {
                for key in map.keys.sorted() { collect(map[key]!, prefix: key) }
            }
        }
        if let message = object["message"] { collect(message, prefix: nil) }
        else if let error = object["error"] { collect(error, prefix: nil) }
        guard !parts.isEmpty else { return nil }
        return sanitise(parts.joined(separator: "；"))
    }

    /// Strips control characters and caps the length of text that came from the server.
    static func sanitise(_ message: String) -> String {
        let cleaned = message.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let text = String(String.UnicodeScalarView(cleaned))
        return text.count > 240 ? String(text.prefix(240)) + "…" : text
    }
}
