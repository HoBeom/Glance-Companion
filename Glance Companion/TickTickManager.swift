//
//  TickTickManager.swift
//  Glance Companion
//
//  Manages TickTick OAuth2 authentication and REST API calls.
//  Fetches tasks and converts them to Glance's ReminderItem format.
//

import Foundation
import CryptoKit

// MARK: - TickTick API Models

struct TickTickProject: Codable, Sendable {
    let id: String
    let name: String
    let closed: Bool?
    let kind: String?
}

struct TickTickTask: Codable, Sendable {
    let id: String
    let projectId: String?
    let title: String
    let content: String?
    let startDate: String?
    let dueDate: String?
    let priority: Int?
    let status: Int?        // 0 = active, 2 = completed

    var isCompleted: Bool { status == 2 }
}

struct TickTickProjectData: Codable, Sendable {
    let project: TickTickProject
    let tasks: [TickTickTask]?
}

// MARK: - OAuth Token

private struct TickTickToken: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int?
    let refreshToken: String?
    let scope: String?
    let createdAt: Date

    var isExpired: Bool {
        guard let expiresIn else { return false }
        return Date().timeIntervalSince(createdAt) > Double(expiresIn - 60)
    }

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case tokenType    = "token_type"
        case expiresIn    = "expires_in"
        case refreshToken = "refresh_token"
        case scope, createdAt
    }
}

// MARK: - TickTickManager

@Observable
final class TickTickManager {

    // ─── Configuration ────────────────────────────────────────────────────────
    // 1. https://developer.ticktick.com 에서 앱 등록 후 아래 값 교체
    // 2. Developer Portal의 Redirect URI 에 "glancecompanion://oauth/callback" 등록
    // 3. Xcode: Target → Info → URL Types → URL Schemes 에 "glancecompanion" 추가
    let clientID     = "YOUR_CLIENT_ID"
    let clientSecret = "YOUR_CLIENT_SECRET"
    let redirectURI  = "glancecompanion://oauth/callback"

    private let authorizeURL = "https://ticktick.com/oauth/authorize"
    private let tokenURL     = "https://ticktick.com/oauth/token"
    private let apiBase      = "https://api.ticktick.com/open/v1"

    // ─── Public State ─────────────────────────────────────────────────────────
    var isAuthenticated: Bool { storedToken != nil && storedToken?.isExpired == false }
    var isLoading = false
    var lastError: String?
    var projects: [TickTickProject] = []
    var cachedRawTasks: [TickTickTask] = []

    // ─── Private ──────────────────────────────────────────────────────────────
    private(set) var codeVerifier = ""
    private let tokenKey = "ticktick_token_v1"

    private var storedToken: TickTickToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: tokenKey) else { return nil }
            return try? JSONDecoder().decode(TickTickToken.self, from: data)
        }
        set {
            if let v = newValue, let data = try? JSONEncoder().encode(v) {
                UserDefaults.standard.set(data, forKey: tokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: tokenKey)
            }
        }
    }

    // MARK: - OAuth2 PKCE

    func buildAuthURL() -> URL? {
        codeVerifier = PKCE.verifier()
        let challenge = PKCE.challenge(from: codeVerifier)
        var c = URLComponents(string: authorizeURL)!
        c.queryItems = [
            .init(name: "client_id",            value: clientID),
            .init(name: "response_type",         value: "code"),
            .init(name: "redirect_uri",          value: redirectURI),
            .init(name: "scope",                 value: "tasks:read tasks:write"),
            .init(name: "state",                 value: UUID().uuidString),
            .init(name: "code_challenge",        value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        return c.url
    }

    func handleCallback(url: URL) async {
        guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            lastError = "OAuth 콜백 파싱 실패"
            return
        }
        await exchangeCode(code)
    }

    private func exchangeCode(_ code: String) async {
        isLoading = true
        defer { isLoading = false }

        var req = URLRequest(url: URL(string: tokenURL)!)
        req.httpMethod = "POST"
        req.setValue(basicAuth(), forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            .init(name: "grant_type",    value: "authorization_code"),
            .init(name: "code",          value: code),
            .init(name: "redirect_uri",  value: redirectURI),
            .init(name: "code_verifier", value: codeVerifier),
        ]
        req.httpBody = body.query?.data(using: .utf8)

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let raw = try JSONDecoder().decode(TickTickToken.self, from: data)
            storedToken = TickTickToken(
                accessToken: raw.accessToken, tokenType: raw.tokenType,
                expiresIn: raw.expiresIn, refreshToken: raw.refreshToken,
                scope: raw.scope, createdAt: Date()
            )
            lastError = nil
        } catch {
            lastError = "토큰 교환 실패: \(error.localizedDescription)"
        }
    }

    func signOut() {
        storedToken = nil
        projects = []
        cachedRawTasks = []
        lastError = nil
    }

    // MARK: - Token Refresh

    private func refreshIfNeeded() async throws {
        guard let token = storedToken, token.isExpired,
              let refresh = token.refreshToken else { return }
        var req = URLRequest(url: URL(string: tokenURL)!)
        req.httpMethod = "POST"
        req.setValue(basicAuth(), forHTTPHeaderField: "Authorization")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            .init(name: "grant_type",    value: "refresh_token"),
            .init(name: "refresh_token", value: refresh),
        ]
        req.httpBody = body.query?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: req)
        let raw = try JSONDecoder().decode(TickTickToken.self, from: data)
        storedToken = TickTickToken(
            accessToken: raw.accessToken, tokenType: raw.tokenType,
            expiresIn: raw.expiresIn, refreshToken: raw.refreshToken ?? refresh,
            scope: raw.scope, createdAt: Date()
        )
    }

    // MARK: - API

    func fetchProjects() async throws -> [TickTickProject] {
        let data = try await apiGET("/project")
        return try JSONDecoder().decode([TickTickProject].self, from: data)
    }

    func fetchTasks(projectID: String) async throws -> [TickTickTask] {
        let data = try await apiGET("/project/\(projectID)/data")
        let pd = try JSONDecoder().decode(TickTickProjectData.self, from: data)
        return pd.tasks ?? []
    }

    /// 미완료 태스크 전체를 Glance ReminderItem 으로 변환하여 반환
    func fetchAsReminders(daysAhead: Int = 7) async throws -> [ReminderItem] {
        guard isAuthenticated else { return [] }
        try await refreshIfNeeded()
        isLoading = true
        defer { isLoading = false }

        let allProjects = try await fetchProjects()
        projects = allProjects.filter { !($0.closed ?? false) }

        let cutoff = Calendar.current.date(byAdding: .day, value: daysAhead, to: Date())!
        let fmt = ISO8601DateFormatter()
        var rawTasks: [TickTickTask] = []
        var reminders: [ReminderItem] = []

        for project in projects {
            let ptasks = (try? await fetchTasks(projectID: project.id)) ?? []
            for task in ptasks where !task.isCompleted {
                if let dueDateStr = task.dueDate ?? task.startDate,
                   let dueDate = fmt.date(from: dueDateStr),
                   dueDate > cutoff { continue }
                rawTasks.append(task)
                reminders.append(task.toReminderItem(projectName: project.name))
            }
        }

        cachedRawTasks = rawTasks
        lastError = nil
        return reminders
    }

    /// X4에서 완료 처리된 TickTick task 완료 API 호출
    func completeTask(taskID: String, projectID: String) async throws {
        let body: [String: Any] = ["id": taskID, "projectId": projectID, "status": 2]
        _ = try await apiPOST("/task/\(taskID)", body: body)
    }

    // MARK: - HTTP Helpers

    private func apiGET(_ path: String) async throws -> Data {
        guard let token = storedToken?.accessToken else { throw URLError(.userAuthenticationRequired) }
        var req = URLRequest(url: URL(string: apiBase + path)!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(resp)
        return data
    }

    private func apiPOST(_ path: String, body: [String: Any]) async throws -> Data {
        guard let token = storedToken?.accessToken else { throw URLError(.userAuthenticationRequired) }
        var req = URLRequest(url: URL(string: apiBase + path)!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        try validate(resp)
        return data
    }

    private func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func basicAuth() -> String {
        "Basic " + Data("\(clientID):\(clientSecret)".utf8).base64EncodedString()
    }
}

// MARK: - TickTickTask → ReminderItem

extension TickTickTask {
    func toReminderItem(projectName: String) -> ReminderItem {
        let fmt = ISO8601DateFormatter()
        let due: Date? = (dueDate ?? startDate).flatMap { fmt.date(from: $0) }
        return ReminderItem(
            title:                  String(title.prefix(64)),
            dueDate:                due,
            priority:               priority ?? 0,
            completed:              isCompleted,
            calendarItemIdentifier: String(id.prefix(48)),
            list:                   String(projectName.prefix(32))
        )
    }
}

// MARK: - PKCE (CryptoKit)

private enum PKCE {
    static func verifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }
    static func challenge(from verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
