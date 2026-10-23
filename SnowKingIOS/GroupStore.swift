import Foundation

final class GroupStore {
    static let shared = GroupStore()

    private let defaults = UserDefaults.standard
    private let key = "snowking.groups.v1"
    private let defaultGroups = ["主力号", "小号池", "挂机组"]

    private init() {}

    var groups: [String] {
        if let stored = defaults.stringArray(forKey: key) { return stored }
        let imported = AccountStore.shared.accounts.map(\.group).filter { $0 != "未分组" }
        let initial = unique(defaultGroups + imported)
        defaults.set(initial, forKey: key)
        return initial
    }

    @discardableResult
    func add(_ name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != "全部", clean != "未分组" else { return false }
        var value = groups
        guard !value.contains(clean) else { return false }
        value.append(clean)
        save(value)
        return true
    }

    @discardableResult
    func rename(_ oldName: String, to newName: String) -> Bool {
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        var value = groups
        guard !clean.isEmpty, clean != "全部", clean != "未分组",
              !value.contains(clean), let index = value.firstIndex(of: oldName) else { return false }
        value[index] = clean
        save(value)
        var accounts = AccountStore.shared.accounts
        for index in accounts.indices where accounts[index].group == oldName { accounts[index].group = clean }
        AccountStore.shared.replace(accounts)
        return true
    }

    func delete(_ name: String) {
        save(groups.filter { $0 != name })
        var accounts = AccountStore.shared.accounts
        for index in accounts.indices where accounts[index].group == name { accounts[index].group = "未分组" }
        AccountStore.shared.replace(accounts)
    }

    func setMembership(accountID: UUID, group: String, included: Bool) {
        AccountStore.shared.update(id: accountID, group: included ? group : "未分组")
    }

    func count(in group: String) -> Int {
        AccountStore.shared.accounts.filter { $0.group == group }.count
    }

    private func save(_ value: [String]) { defaults.set(unique(value), forKey: key) }

    private func unique(_ value: [String]) -> [String] {
        var seen = Set<String>()
        return value.filter { seen.insert($0).inserted }
    }
}
