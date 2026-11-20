import Foundation
import Observation
import Security

struct AccountUser: Decodable {
    let id: String
    let nickname: String
}

private struct AuthResponse: Decodable {
    let token: String
    let user: AccountUser
}

private struct EmailBody: Encodable {
    let email: String
}

private struct VerifyBody: Encodable {
    let email: String
    let code: String
}

private struct SendResponse: Decodable {
    let ok: Bool
}

@MainActor
@Observable
final class AccountSession {
    private static let keychainService = "app.zhixing.session"
    private static let keychainAccount = "token"

    private(set) var user: AccountUser?
    private(set) var token: String?
    private(set) var restoring = true

    var isSignedIn: Bool { token != nil }

    func restore() async {
        defer { restoring = false }
        guard let savedToken = try? Self.readToken() else { return }
        token = savedToken
        do {
            user = try await APIClient.get("/me", bearer: savedToken)
        } catch APIError.badResponse(401) {
            try? Self.deleteToken()
            token = nil
        } catch {
            // A transient network error should not erase a valid local session.
        }
    }

    func sendRegistrationCode(email: String) async throws {
        let _: SendResponse = try await APIClient.post("/auth/email/send", body: EmailBody(email: email))
    }

    func registerOrSignIn(email: String, code: String) async throws {
        let response: AuthResponse = try await APIClient.post(
            "/auth/email/verify", body: VerifyBody(email: email, code: code))
        try Self.saveToken(response.token)
        token = response.token
        user = response.user
    }

    private struct RegisterBody: Encodable { let email: String; let code: String; let password: String }
    func register(email: String, code: String, password: String) async throws {
        let response: AuthResponse = try await APIClient.post(
            "/auth/email/register", body: RegisterBody(email: email, code: code, password: password))
        try Self.saveToken(response.token)
        token = response.token
        user = response.user
    }

    private struct PasswordBody: Encodable { let email: String; let password: String }
    func signIn(email: String, password: String) async throws {
        let response: AuthResponse = try await APIClient.post(
            "/auth/email/password", body: PasswordBody(email: email, password: password))
        try Self.saveToken(response.token)
        token = response.token
        user = response.user
    }

    func sendPasswordResetCode(email: String) async throws {
        let _: SendResponse = try await APIClient.post("/auth/password-reset/send", body: EmailBody(email: email))
    }

    private struct PasswordResetBody: Encodable { let email: String; let code: String; let password: String }
    func resetPassword(email: String, code: String, password: String) async throws {
        let _: SendResponse = try await APIClient.post(
            "/auth/password-reset", body: PasswordResetBody(email: email, code: code, password: password))
    }

    private static func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
        ]
    }

    private static func readToken() throws -> String? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status)
        }
        return String(data: data, encoding: .utf8)
    }

    private static func saveToken(_ token: String) throws {
        let query = keychainQuery()
        let data = Data(token.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status) }
        var item = query
        item[kSecValueData as String] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(addStatus) }
    }

    private static func deleteToken() throws {
        let status = SecItemDelete(keychainQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status) }
    }
}

private struct KeychainError: LocalizedError {
    let status: OSStatus
    init(_ status: OSStatus) { self.status = status }
    var errorDescription: String? { "无法安全保存登录状态（\(status)），请重试。" }
}
