import Foundation
import Security

struct Account: Codable {
    // The identifier also selects an independent persistent WebKit data store (iOS 17+).
    var id: UUID = UUID()
    var name: String = ""
    var cdk: String = ""

    static func normalize(_ input: String) throws -> String {
        let value = input.uppercased().unicodeScalars.filter {
            (65...90).contains($0.value) || (48...57).contains($0.value)
        }.map(String.init).joined()
        guard (16...64).contains(value.count) else { throw ClientError.message("请输入完整 CDK") }
        return value
    }
}

enum ClientError: LocalizedError {
    case message(String)
    case business(String)

    var errorDescription: String? {
        switch self { case .message(let text), .business(let text): return text }
    }
}

struct AccountVault {
    private let service = "cn.duokai.ios.accounts.v1"

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "six-slots"]
    }

    func load() throws -> [Account] {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return (0..<6).map { _ in Account() } }
        guard status == errSecSuccess, let data = item as? Data else {
            throw ClientError.message("无法读取安全存储，请解锁设备后重试")
        }
        let accounts = try JSONDecoder().decode([Account].self, from: data)
        guard accounts.count == 6, Set(accounts.map(\.id)).count == 6 else {
            throw ClientError.message("账号存储格式异常，未覆盖原数据")
        }
        return accounts
    }

    func save(_ accounts: [Account]) throws {
        let data = try JSONEncoder().encode(accounts)
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw ClientError.message("保存 CDK 失败，请解锁设备后重试") }
    }
}
