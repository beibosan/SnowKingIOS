import Foundation

struct SnowAccount: Codable, Equatable {
    let id: UUID
    var name: String
    var group: String
    var importedAt: Date
    var updatedAt: Date?
    var binData: String?
    var decodedLoginInfo: String?
    var decodedBinHash: String?
    var lineupData: [String: String]?
    var serverId: String?
    var status: String?
    var lastOperation: String?
    var sourceFileName: String?

    var displayStatus: String { status ?? "待机" }
    var displayDate: Date { updatedAt ?? importedAt }
    var dataSize: Int { Data(base64Encoded: binData ?? "")?.count ?? 0 }
}

final class AccountStore {
    static let shared = AccountStore()
    private let key = "snowking.accounts.v1"
    private let defaults = UserDefaults.standard

    private init() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        migrateLegacyDefaultsIfNeeded()
    }

    private var directoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SnowKingAccounts", isDirectory: true)
    }

    private var metadataURL: URL { directoryURL.appendingPathComponent("accounts.json") }

    var storageURL: URL { directoryURL }

    var storageSize: Int64 {
        let values = try? FileManager.default.attributesOfItem(atPath: metadataURL.path)
        return (values?[.size] as? NSNumber)?.int64Value ?? 0
    }

    var accounts: [SnowAccount] {
        guard let data = try? Data(contentsOf: metadataURL),
              let value = try? JSONDecoder().decode([SnowAccount].self, from: data) else { return [] }
        return value
    }

    func add(name: String, group: String = "未分组") {
        var value = accounts
        value.append(SnowAccount(id: UUID(), name: name, group: group, importedAt: Date(), updatedAt: Date(), binData: nil, decodedLoginInfo: nil, decodedBinHash: nil, lineupData: nil, serverId: nil, status: "待机", lastOperation: "新建账号", sourceFileName: nil))
        save(value)
    }

    func addImported(name: String, data: Data, fileName: String? = nil, group: String = "未分组", serverId: String? = nil) {
        var value = accounts
        if fileName?.lowercased().hasSuffix(".json") == true,
           let restored = try? JSONDecoder().decode(SnowAccount.self, from: data) {
            value.append(SnowAccount(
                id: UUID(),
                name: restored.name.isEmpty ? name : restored.name,
                group: restored.group.isEmpty ? group : restored.group,
                importedAt: Date(),
                updatedAt: Date(),
                binData: restored.binData,
                decodedLoginInfo: restored.decodedLoginInfo,
                decodedBinHash: restored.decodedBinHash,
                lineupData: restored.lineupData,
                serverId: serverId ?? restored.serverId,
                status: "待机",
                lastOperation: "导入 JSON 账号",
                sourceFileName: fileName
            ))
            save(value)
            return
        }
        value.append(SnowAccount(
            id: UUID(),
            name: name,
            group: group,
            importedAt: Date(),
            updatedAt: Date(),
            binData: data.base64EncodedString(),
            decodedLoginInfo: nil,
            decodedBinHash: nil,
            lineupData: nil,
            serverId: serverId,
            status: "待机",
            lastOperation: "导入账号",
            sourceFileName: fileName
        ))
        save(value)
    }

    func remove(at index: Int) {
        var value = accounts
        guard value.indices.contains(index) else { return }
        value.remove(at: index)
        save(value)
    }

    func replace(_ value: [SnowAccount]) { save(value) }

    func update(id: UUID, name: String? = nil, group: String? = nil) {
        var value = accounts
        guard let index = value.firstIndex(where: { $0.id == id }) else { return }
        if let name { value[index].name = name }
        if let group { value[index].group = group }
        save(value)
    }

    func updateStatus(ids: Set<UUID>, status: String, operation: String) {
        var value = accounts
        let now = Date()
        for index in value.indices where ids.contains(value[index].id) {
            value[index].status = status
            value[index].lastOperation = operation
            value[index].updatedAt = now
        }
        save(value)
    }

    func updateDecodedLoginInfo(accountID: UUID, value decoded: String, binHash: String) {
        var value = accounts
        guard let index = value.firstIndex(where: { $0.id == accountID }) else { return }
        value[index].decodedLoginInfo = decoded
        value[index].decodedBinHash = binHash
        value[index].updatedAt = Date()
        save(value)
    }

    func updateLineupData(accountID: UUID, key: String, value lineupJSON: String) {
        guard !key.isEmpty else { return }
        var value = accounts
        guard let index = value.firstIndex(where: { $0.id == accountID }) else { return }
        var lineups = value[index].lineupData ?? [:]
        lineups[key] = lineupJSON
        value[index].lineupData = lineups
        value[index].updatedAt = Date()
        save(value)
    }

    private func save(_ value: [SnowAccount]) {
        do {
            let data = try JSONEncoder().encode(value)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            backupCorruptMetadataIfNeeded()
            try data.write(to: metadataURL, options: .atomic)
        } catch {
            NSLog("[SnowKing] account save failed: %@", error.localizedDescription)
        }
    }

    private func backupCorruptMetadataIfNeeded() {
        guard FileManager.default.fileExists(atPath: metadataURL.path),
              let existing = try? Data(contentsOf: metadataURL),
              (try? JSONDecoder().decode([SnowAccount].self, from: existing)) == nil else { return }
        let backup = directoryURL.appendingPathComponent("accounts-corrupt-\(Int(Date().timeIntervalSince1970)).json")
        do {
            try FileManager.default.copyItem(at: metadataURL, to: backup)
        } catch {
            NSLog("[SnowKing] corrupt account backup failed: %@", error.localizedDescription)
        }
    }

    private func migrateLegacyDefaultsIfNeeded() {
        guard !FileManager.default.fileExists(atPath: metadataURL.path),
              let data = defaults.data(forKey: key),
              (try? JSONDecoder().decode([SnowAccount].self, from: data)) != nil else { return }
        try? data.write(to: metadataURL, options: .atomic)
        defaults.removeObject(forKey: key)
    }
}
