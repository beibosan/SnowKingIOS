import Foundation

struct LocalScript: Equatable {
    let name: String
    let url: URL
    var enabled: Bool
    var size: Int
    var modifiedAt: Date
}

struct BuiltinScript: Equatable {
    let name: String
    let fileName: String
    let category: String
    let description: String
    let defaultEnabled: Bool
    var enabled: Bool
}

final class LocalScriptStore {
    static let shared = LocalScriptStore()
    private let defaults = UserDefaults.standard
    private let enabledKey = "snowking.local-scripts.enabled"
    private var builtInNames: Set<String> {
        let legacy = ["声音关闭.js", "阵容数据.js", "auto-mute.js", "lineup-manager.js",
                      "ten-dungeons-speed.js", "hide-first-login-popups.js"]
        return Set(legacy).union(BuiltinScriptStore.catalog.map { $0.fileName + ".js" })
    }
    private let cacheLock = NSLock()
    private var sourceCache: [String: String] = [:]

    private init() { ensureDirectory() }

    var directoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LocalScripts", isDirectory: true)
    }

    var storageSize: Int64 {
        scripts.reduce(0) { $0 + Int64($1.size) }
    }

    var scripts: [LocalScript] {
        ensureDirectory()
        let enabled = defaults.stringArray(forKey: enabledKey) ?? []
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return urls
            .filter { $0.pathExtension.lowercased() == "js" && !builtInNames.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                return LocalScript(
                    name: url.lastPathComponent,
                    url: url,
                    enabled: enabled.contains(url.lastPathComponent),
                    size: values?.fileSize ?? 0,
                    modifiedAt: values?.contentModificationDate ?? .distantPast
                )
            }
    }

    var enabledScripts: [(name: String, source: String)] {
        scripts.filter(\.enabled).compactMap { item in
            let key = item.url.standardizedFileURL.path
            cacheLock.lock()
            let cached = sourceCache[key]
            cacheLock.unlock()
            if let cached { return (item.name, cached) }
            guard let source = try? String(contentsOf: item.url, encoding: .utf8) else { return nil }
            cacheLock.lock()
            sourceCache[key] = source
            cacheLock.unlock()
            return (item.name, source)
        }
    }

    func setEnabled(_ enabled: Bool, for script: LocalScript) {
        var names = Set(defaults.stringArray(forKey: enabledKey) ?? [])
        let wasEnabled = names.contains(script.name)
        if enabled { names.insert(script.name) } else { names.remove(script.name) }
        defaults.set(Array(names).sorted(), forKey: enabledKey)
        if wasEnabled != enabled {
            NotificationCenter.default.post(name: .snowKingScriptsChanged, object: nil)
        }
    }

    func importScript(from sourceURL: URL) throws {
        guard sourceURL.pathExtension.lowercased() == "js" else { throw CocoaError(.fileReadUnsupportedScheme) }
        guard !builtInNames.contains(sourceURL.lastPathComponent) else { throw CocoaError(.fileWriteInvalidFileName) }
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: sourceURL)
        guard let source = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        ensureDirectory()
        let destination = directoryURL.appendingPathComponent(sourceURL.lastPathComponent)
        if destination != sourceURL { try data.write(to: destination, options: .atomic) }
        cacheLock.lock()
        sourceCache[destination.standardizedFileURL.path] = source
        cacheLock.unlock()
    }

    func delete(_ script: LocalScript) throws {
        setEnabled(false, for: script)
        try FileManager.default.removeItem(at: script.url)
        cacheLock.lock()
        sourceCache.removeValue(forKey: script.url.standardizedFileURL.path)
        cacheLock.unlock()
    }

    private func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}

enum BuiltinScriptStore {
    private static let enabledKey = "snowking.builtin-scripts.enabled"

    static let catalog: [(name: String, fileName: String, category: String, description: String, defaultEnabled: Bool)] = [
        ("玩家信息增强", "玩家信息增强", "日常辅助", "扩展玩家信息显示", true),
        ("英雄面板增强", "英雄面板增强", "日常辅助", "扩展英雄面板信息", true),
        ("跳过宝箱动画", "跳过宝箱动画", "日常辅助", "跳过宝箱开启动画", true),
        ("洗炼增强面板", "洗炼增强面板", "日常辅助", "增强洗炼操作面板", false),
        ("装备洗练消耗显示", "装备洗练消耗显示", "日常辅助", "显示洗炼材料消耗", false),
        ("四圣升级", "四圣升级", "日常辅助", "自动执行四圣升级", false),
        ("更换头像", "更换头像", "日常辅助", "修改游戏内头像", false),
        ("模拟对战", "模拟对战", "日常辅助", "模拟战斗并查看结果", false),
        ("十殿倒计时", "十殿倒计时", "十殿", "显示十殿战斗倒计时", false),
        ("十殿自动组队", "十殿自动组队（一键组队）", "十殿", "自动匹配并组建队伍", false),
        ("盐场加速+刨地", "盐场加速+刨地", "盐场", "自动加速与攻击建筑", false),
        ("盐场攻击弹窗不消失", "盐场攻击弹窗不消失", "盐场", "保留盐场攻击弹窗", false),
        ("盐场无限视距", "盐场无限视距", "盐场", "扩展盐场可视范围", false),
        ("盐场显示阵容", "盐场显示阵容(1)", "盐场", "识别并显示盐场阵容", false),
        ("全自动蟠桃园", "全自动蟠桃园", "蟠桃", "辅助蟠桃园任务", false)
    ]

    static var scripts: [BuiltinScript] {
        let enabled = enabledNames()
        return catalog.compactMap {
            guard GameAssetStore.shared.url(forResource: $0.fileName, withExtension: "js", subdirectory: "builtin") != nil else { return nil }
            return BuiltinScript(name: $0.name, fileName: $0.fileName, category: $0.category,
                          description: $0.description, defaultEnabled: $0.defaultEnabled,
                          enabled: enabled.contains($0.fileName))
        }
    }

    static func setEnabled(_ enabled: Bool, for script: BuiltinScript) {
        var names = enabledNames()
        let old = names.contains(script.fileName)
        if enabled { names.insert(script.fileName) } else { names.remove(script.fileName) }
        UserDefaults.standard.set(Array(names).sorted(), forKey: enabledKey)
        if old != enabled {
            NotificationCenter.default.post(name: .snowKingScriptsChanged, object: nil)
        }
    }

    static var enabledSources: [(name: String, source: String)] {
        var result: [(String, String)] = []
        let defaults = UserDefaults.standard
        let muted = defaults.object(forKey: "sound_muted") == nil ? false : defaults.bool(forKey: "sound_muted")
        let speed = defaults.bool(forKey: "speed_enabled")
        let popupHidden = defaults.bool(forKey: "popup_hidden")

        if muted, let sound = source(named: "auto-mute") {
            result.append(("声音关闭", sound))
        } else if defaults.bool(forKey: "sound_restore_pending"), let sound = source(named: "auto-unmute") {
            result.append(("声音恢复", sound))
            defaults.removeObject(forKey: "sound_restore_pending")
        }
        if speed, let script = source(named: "ten-dungeons-speed") {
            result.append(("十殿加速", script))
        }
        if popupHidden, let script = source(named: "hide-first-login-popups") {
            result.append(("隐藏弹窗", script))
        }
        return result
    }

    static var enabledManagedSources: [(name: String, source: String)] {
        scripts.filter(\.enabled).compactMap { script in
            guard let source = source(named: script.fileName) else { return nil }
            return (script.name, source)
        }
    }

    private static func enabledNames() -> Set<String> {
        let defaults = UserDefaults.standard
        if let stored = defaults.stringArray(forKey: enabledKey) {
            return Set(stored)
        }
        let initial = Set(catalog.filter(\.defaultEnabled).map { $0.fileName })
        defaults.set(Array(initial).sorted(), forKey: enabledKey)
        return initial
    }

    private static func source(named name: String) -> String? {
        guard let url = GameAssetStore.shared.url(forResource: name, withExtension: "js", subdirectory: "builtin") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
