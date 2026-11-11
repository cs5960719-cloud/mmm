import Foundation
import CryptoKit

struct LoginReply: Decodable {
    let ok: Bool
    let url: String
    let server: String
    let role_id: String?
    let expire_at: Int
}

struct ScriptManifest: Decodable {
    let ok: Bool
    let sha256: String
    let size: Int
}

struct GameBundle {
    let login: LoginReply
    let script: String
}

// Never send CDK credentials through HTTP redirects or the game page's cookie store.
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

final class APIClient {
    private let session: URLSession
    private let bases = ["https://cs.d57.net", "https://hk.d57.net"]
    private let limit = 4 * 1024 * 1024

    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 95
        configuration.timeoutIntervalForResource = 110
        self.session = session ?? URLSession(configuration: configuration, delegate: NoRedirect(), delegateQueue: nil)
    }

    static func gameURL(_ text: String) throws -> URL {
        guard let url = URL(string: text), let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else {
            throw ClientError.message("后台返回的游戏地址无效")
        }
        return url
    }

    static func verifiedScript(_ data: Data, manifest: ScriptManifest, header: String?) throws -> String {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard manifest.ok, manifest.size > 0, manifest.size == data.count, data.count <= 4 * 1024 * 1024,
              hash == manifest.sha256.lowercased(), header?.lowercased() == hash,
              let script = String(data: data, encoding: .utf8) else {
            throw ClientError.message("脚本完整性校验失败，请重新打开窗口")
        }
        return script
    }

    func open(cdk: String) async throws -> GameBundle {
        var last: Error = ClientError.message("服务暂不可用")
        for base in bases {
            try Task.checkCancellation()
            do {
                let (loginData, _) = try await post(base, "login", cdk)
                let login = try JSONDecoder().decode(LoginReply.self, from: loginData)
                guard login.ok, login.expire_at > Int(Date().timeIntervalSince1970) else {
                    throw ClientError.business("CDK 已过期或登录无效")
                }
                _ = try Self.gameURL(login.url)
                // Fetch both on every open/restart. No script or manifest is persisted locally.
                let (manifestData, _) = try await post(base, "script_version", cdk)
                let manifest = try JSONDecoder().decode(ScriptManifest.self, from: manifestData)
                let (scriptData, response) = try await post(base, "script", cdk)
                let script = try Self.verifiedScript(scriptData, manifest: manifest,
                    header: response.value(forHTTPHeaderField: "X-Script-Sha256"))
                return GameBundle(login: login, script: script)
            } catch is CancellationError { throw CancellationError() }
            catch let error as ClientError {
                if case .business = error { throw error }
                last = error
            } catch { last = error }
        }
        // Never expose transport URLs, game tokens, or request bodies in user-facing errors.
        if let error = last as? ClientError { throw error }
        throw ClientError.message("登录或获取脚本失败，请检查网络后重试")
    }

    private func post(_ base: String, _ endpoint: String, _ cdk: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: URL(string: "\(base)/api/\(endpoint).php")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 95)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(["cdk": cdk])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-store, no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw ClientError.message("服务响应无效") }
        guard response.expectedContentLength <= limit else { throw ClientError.message("服务响应过大") }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw ClientError.message("服务响应过大") }
            data.append(byte)
        }
        guard response.statusCode == 200 else {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = json?["error"] as? String ?? "服务暂不可用（\(response.statusCode)）"
            let safe = detail.count < 180 && !detail.contains("://") ? detail : "服务暂不可用"
            if (400..<500).contains(response.statusCode), ![408, 429].contains(response.statusCode) {
                throw ClientError.business(safe)
            }
            throw ClientError.message(safe)
        }
        if endpoint.hasPrefix("script") {
            let directives = (response.value(forHTTPHeaderField: "Cache-Control") ?? "")
                .lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard directives.contains("no-store") else {
                throw ClientError.message("脚本接口未禁止缓存，已停止加载")
            }
        }
        return (data, response)
    }
}
