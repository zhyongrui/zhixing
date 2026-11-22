import Foundation

enum APIClient {
    static var baseURL: URL {
        if let value = Bundle.main.object(forInfoDictionaryKey: "APIBase") as? String,
           let url = URL(string: value), !value.isEmpty {
            return url
        }
        #if DEBUG
        return URL(string: "http://localhost:8787")!
        #else
        preconditionFailure("请在构建设置中配置 APP_API_BASE")
        #endif
    }

    static func get<Value: Decodable>(
        _ path: String,
        timeout: TimeInterval = 20,
        bearer: String? = nil
    ) async throws -> Value {
        let url = URL(string: path, relativeTo: baseURL)!.absoluteURL
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        return try decode(Value.self, data: data, response: response)
    }

    static func post<Body: Encodable, Value: Decodable>(
        _ path: String,
        body: Body,
        timeout: TimeInterval = 20,
        bearer: String? = nil
    ) async throws -> Value {
        let url = URL(string: path, relativeTo: baseURL)!.absoluteURL
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        return try decode(Value.self, data: data, response: response)
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        data: Data,
        response: URLResponse
    ) throws -> Value {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw APIError.badResponse(status)
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

enum APIError: LocalizedError {
    case badResponse(Int)

    var errorDescription: String? {
        switch self {
        case .badResponse(401): "验证码错误或已过期，请重新获取。"
        case .badResponse(429): "操作太频繁，请稍后再试。"
        case .badResponse(409): "这个邮箱已经注册，请直接登录。"
        case .badResponse: "服务暂时无法响应，请检查网络后重试。"
        }
    }
}
