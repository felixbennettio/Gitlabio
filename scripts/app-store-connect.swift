import Foundation
import CryptoKit

// Used only by the publishing job. Never prints a JWT, key, issuer or key ID.
private struct PublishError: LocalizedError {
    let message: String
    var httpStatus: Int? = nil
    var errorDescription: String? { message }
}
private func required(_ name: String) throws -> String {
    guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
        throw PublishError(message: "Required publishing setting is missing: \(name)")
    }
    return value
}
private func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
private final class AppStore {
    let key: P256.Signing.PrivateKey
    let issuer: String
    let keyID: String
    let session: URLSession
    let delegate = NoRedirects()
    init() throws {
        key = try P256.Signing.PrivateKey(pemRepresentation: String(contentsOfFile: required("GITLABIO_ASC_KEY_PATH"), encoding: .utf8))
        issuer = try required("APP_STORE_CONNECT_ISSUER_ID")
        keyID = try required("APP_STORE_CONNECT_KEY_ID")
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45
        session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
    func token() throws -> String {
        let now = Int(Date().timeIntervalSince1970)
        let header = try JSONSerialization.data(withJSONObject: ["alg": "ES256", "kid": keyID, "typ": "JWT"])
        let payload = try JSONSerialization.data(withJSONObject: ["iss": issuer, "iat": now - 10, "exp": now + 600, "aud": "appstoreconnect-v1"])
        let input = base64URL(header) + "." + base64URL(payload)
        return input + "." + base64URL(try key.signature(for: Data(input.utf8)).rawRepresentation)
    }
    func request(_ path: String, query: [URLQueryItem] = [], body: [String: Any]? = nil) async throws -> [String: Any] {
        var parts = URLComponents(string: "https://api.appstoreconnect.apple.com/v1/" + path)!
        parts.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: parts.url!)
        request.setValue("Bearer " + (try token()), forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw PublishError(message: "Invalid Apple API response") }
        guard (200..<300).contains(response.statusCode) else {
            let errorJSON = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let codes = (errorJSON?["errors"] as? [[String: Any]] ?? []).compactMap { $0["code"] as? String }
                .filter { $0.range(of: "^[A-Z0-9._-]+$", options: .regularExpression) != nil }
            let parameters = (errorJSON?["errors"] as? [[String: Any]] ?? []).compactMap {
                ($0["source"] as? [String: Any])?["parameter"] as? String
            }.filter { $0.range(of: "^[A-Za-z0-9_\\[\\].-]+$", options: .regularExpression) != nil }
            throw PublishError(message: "App Store Connect API failed (HTTP \(response.statusCode), resource \(path), codes \(codes.joined(separator: ",")), parameters \(parameters.joined(separator: ",")))", httpStatus: response.statusCode)
        }
        if data.isEmpty { return [:] }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw PublishError(message: "Invalid Apple API JSON") }
        return json
    }
    func app(bundleID: String) async throws -> [String: Any] {
        let result = try await request("apps", query: [.init(name: "filter[bundleId]", value: bundleID), .init(name: "limit", value: "2")])
        guard let apps = result["data"] as? [[String: Any]], apps.count == 1,
              let attributes = apps[0]["attributes"] as? [String: Any], attributes["bundleId"] as? String == bundleID else {
            throw PublishError(message: "The existing App Store Connect app does not match \(bundleID)")
        }
        return apps[0]
    }
}

@main private struct AppStoreConnect {
    static func main() async {
        do { try await run() }
        catch {
            // Crypto errors are deliberately kept generic; error diagnostics must not include key material.
            let message = (error as? PublishError)?.message ?? "App Store Connect operation failed; check the API key, signing permissions and network."
            FileHandle.standardError.write(Data((message + "\n").utf8))
            exit(1)
        }
    }
    static func run() async throws {
        guard CommandLine.arguments.count == 3 else { throw PublishError(message: "Usage: app-store-connect preflight|wait|distribute result.json") }
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let store = try AppStore()
        let bundleID = "io.routeforge.gitlabio"
        let app = try await store.app(bundleID: bundleID)
        guard let appID = app["id"] as? String else { throw PublishError(message: "App record is missing its ID") }
        let attributes = app["attributes"] as? [String: Any] ?? [:]
        if CommandLine.arguments[1] == "distribute" {
            try await distribute(store: store, appID: appID, bundleID: bundleID, output: output)
        } else if CommandLine.arguments[1] == "preflight" {
            let builds = try await store.request("builds", query: [.init(name: "filter[app]", value: appID), .init(name: "limit", value: "200"), .init(name: "sort", value: "-uploadedDate")])
            let previous = (builds["data"] as? [[String: Any]] ?? []).compactMap {
                (($0["attributes"] as? [String: Any])?["version"] as? String).flatMap(Int.init)
            }.max() ?? 0
            let job = Int(try required("CI_JOB_ID")) ?? 1
            let number = max(job + 2000, previous + 1)
            let result: [String: Any] = ["appID": appID, "bundleID": bundleID, "name": attributes["name"] ?? "Gitlabio", "buildNumber": String(number)]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
            print("Verified existing App Store app \(bundleID); build number \(number)")
        } else if CommandLine.arguments[1] == "wait" {
            let number = try required("GITLABIO_BUILD_NUMBER")
            var previous = ""
            for attempt in 0..<40 {
                let response = try await store.request("builds", query: [.init(name: "filter[app]", value: appID), .init(name: "filter[version]", value: number), .init(name: "limit", value: "1")])
                let build = (response["data"] as? [[String: Any]])?.first
                let details = build?["attributes"] as? [String: Any] ?? [:]
                let state = details["processingState"] as? String ?? "AWAITING_APPLE_INGESTION"
                if state != previous { print("Apple build processing: \(state)"); previous = state }
                if state == "INVALID" || state == "FAILED" { throw PublishError(message: "Apple rejected processing of build \(number): \(state)") }
                if state == "VALID", let buildID = build?["id"] as? String {
                    let groups = try await store.request("apps/\(appID)/betaGroups", query: [.init(name: "limit", value: "200")])
                    let internalGroups = (groups["data"] as? [[String: Any]] ?? []).filter {
                        ($0["attributes"] as? [String: Any])?["isInternalGroup"] as? Bool == true
                    }
                    var assigned = 0
                    for group in internalGroups {
                        guard let groupID = group["id"] as? String else { continue }
                        let values = group["attributes"] as? [String: Any] ?? [:]
                        if values["hasAccessToAllBuilds"] as? Bool != true {
                            _ = try await store.request("betaGroups/\(groupID)/relationships/builds", body: ["data": [["type": "builds", "id": buildID]]])
                        }
                        assigned += 1
                    }
                    let result: [String: Any] = ["appID": appID, "bundleID": bundleID, "buildNumber": number, "buildID": buildID,
                        "processingState": state, "internalGroups": assigned,
                        "distribution": assigned > 0 ? "available-to-existing-internal-groups" : "ready-in-testflight-no-existing-internal-group"]
                    try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
                    print("TestFlight build \(number) is VALID; existing internal groups: \(assigned)")
                    return
                }
                if attempt < 39 { try await Task.sleep(nanoseconds: 30_000_000_000) }
            }
            throw PublishError(message: "Upload was accepted but Apple processing has not completed within 20 minutes")
        } else { throw PublishError(message: "Unknown publishing operation") }
    }
}

private func distribute(store: AppStore, appID: String, bundleID: String, output: URL) async throws {
    let email = try required("GITLABIO_TESTER_EMAIL").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let number = try required("GITLABIO_BUILD_NUMBER")
    guard email.count <= 254, email.contains("@"), email.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }),
          !number.isEmpty, number.allSatisfy(\.isNumber) else {
        throw PublishError(message: "Invalid tester email or build number")
    }
    // Internal testing never grants a new App Store Connect role.
    let users = try await store.request("users", query: [.init(name: "filter[username]", value: email), .init(name: "limit", value: "2")])
    let matches = (users["data"] as? [[String: Any]] ?? []).filter {
        (($0["attributes"] as? [String: Any])?["username"] as? String)?.lowercased() == email
    }
    guard matches.count == 1, let userID = matches[0]["id"] as? String,
          let user = matches[0]["attributes"] as? [String: Any], let roles = user["roles"] as? [String],
          !Set(roles).isDisjoint(with: ["ACCOUNT_HOLDER", "ADMIN", "APP_MANAGER", "DEVELOPER", "MARKETING"]) else {
        throw PublishError(message: "The requested email is not an eligible existing internal team tester; no team role was changed")
    }
    if user["allAppsVisible"] as? Bool != true {
        let visible = try await store.request("users/\(userID)/visibleApps", query: [.init(name: "limit", value: "200")])
        guard (visible["data"] as? [[String: Any]] ?? []).contains(where: { $0["id"] as? String == appID }) else {
            throw PublishError(message: "The requested team tester does not have access to Gitlabio")
        }
    }
    let builds = try await store.request("builds", query: [.init(name: "filter[app]", value: appID),
        .init(name: "filter[version]", value: number), .init(name: "limit", value: "2")])
    guard let values = builds["data"] as? [[String: Any]], values.count == 1, let buildID = values[0]["id"] as? String,
          let build = values[0]["attributes"] as? [String: Any], build["processingState"] as? String == "VALID",
          build["expired"] as? Bool != true else {
        throw PublishError(message: "The selected Gitlabio build is not VALID and available for testing")
    }
    let groupName = "Gitlabio TF"
    let groups = try await store.request("apps/\(appID)/betaGroups", query: [.init(name: "limit", value: "200")])
    let existingGroups = (groups["data"] as? [[String: Any]] ?? []).filter {
        let a = $0["attributes"] as? [String: Any] ?? [:]
        return a["name"] as? String == groupName && a["isInternalGroup"] as? Bool == true
    }
    guard existingGroups.count <= 1 else { throw PublishError(message: "Multiple matching internal groups require review") }
    let group: [String: Any]
    if let existing = existingGroups.first { group = existing }
    else {
        let created = try await store.request("betaGroups", body: ["data": ["type": "betaGroups",
            "attributes": ["name": groupName, "isInternalGroup": true, "hasAccessToAllBuilds": false],
            "relationships": ["app": ["data": ["type": "apps", "id": appID]]]]])
        guard let value = created["data"] as? [String: Any] else { throw PublishError(message: "Apple did not return the created internal group") }
        group = value
    }
    guard let groupID = group["id"] as? String else { throw PublishError(message: "Internal group ID is missing") }
    _ = try await store.request("betaGroups/\(groupID)/relationships/builds", body: ["data": [["type": "builds", "id": buildID]]])
    func members() async throws -> [[String: Any]] {
        let response = try await store.request("betaGroups/\(groupID)/betaTesters", query: [.init(name: "limit", value: "200")])
        guard (response["links"] as? [String: Any])?["next"] as? String == nil else {
            throw PublishError(message: "Internal group member pagination requires review")
        }
        return response["data"] as? [[String: Any]] ?? []
    }
    let currentMember = try await members().first {
        (($0["attributes"] as? [String: Any])?["email"] as? String)?.lowercased() == email
    }
    let testerID: String
    if let id = currentMember?["id"] as? String {
        testerID = id
    } else {
        // Internal membership is created atomically for this app. Linking a
        // global external tester identity into an internal group is rejected
        // by Apple's state machine, even when its email matches a team user.
        var testerAttributes: [String: Any] = ["email": email]
        for name in ["firstName", "lastName"] {
            if let value = user[name] as? String, !value.isEmpty { testerAttributes[name] = value }
        }
        let created = try await store.request("betaTesters", body: ["data": ["type": "betaTesters",
            "attributes": testerAttributes,
            "relationships": ["betaGroups": ["data": [["type": "betaGroups", "id": groupID]]]]]])
        guard let value = created["data"] as? [String: Any], let id = value["id"] as? String else {
            throw PublishError(message: "Apple did not return the created tester")
        }
        testerID = id
    }
    let groupBuilds = try await store.request("betaGroups/\(groupID)/relationships/builds", query: [.init(name: "limit", value: "200")])
    guard (groupBuilds["data"] as? [[String: Any]] ?? []).contains(where: { $0["id"] as? String == buildID }) else {
        throw PublishError(message: "The build-to-group assignment was not confirmed")
    }
    var invitationRequested = false
    for attempt in 0..<10 {
        let tester = try await members().first(where: { $0["id"] as? String == testerID })
        let state = (tester?["attributes"] as? [String: Any])?["state"] as? String ?? "UNKNOWN"
        if ["INVITED", "ACCEPTED", "INSTALLED"].contains(state) {
            let result: [String: Any] = ["appID": appID, "bundleID": bundleID, "buildNumber": number, "buildID": buildID,
                "groupID": groupID, "groupName": groupName, "isInternalGroup": true, "testerEmail": email,
                "testerState": state, "invitation": state == "INVITED" ? "confirmed-by-apple" : "tester-already-accepted",
                "explicitInvitationRequested": invitationRequested,
                "buildAssigned": true, "testerAssigned": true]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
            print("Internal TestFlight group and build assignment verified; tester state: \(state)")
            return
        }
        if ["NOT_INVITED", "REVOKED"].contains(state), !invitationRequested {
            _ = try await store.request("betaTesterInvitations", body: ["data": ["type": "betaTesterInvitations",
                "relationships": ["app": ["data": ["type": "apps", "id": appID]],
                    "betaTester": ["data": ["type": "betaTesters", "id": testerID]]]]])
            invitationRequested = true
        }
        if attempt < 9 { try await Task.sleep(nanoseconds: 3_000_000_000) }
    }
    throw PublishError(message: "Tester was assigned, but Apple has not yet confirmed an invited or accepted state")
}
