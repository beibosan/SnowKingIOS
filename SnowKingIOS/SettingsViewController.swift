import UIKit
import UniformTypeIdentifiers
import WebKit

final class SettingsViewController: UIViewController {
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let preferences = UserDefaults.standard

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.page
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        let stackWidth = stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -28)
        stackWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 7),
            stack.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor),
            stackWidth,
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 760),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -34)
        ])
        buildSettings()
    }

    private func buildSettings() {
        addSection("功能设置", rows: [
            navigationRow(icon: "scroll", title: "脚本管理", subtitle: "管理外置 .js 脚本", color: Theme.palette.lavenderSoft, action: #selector(openLocalScripts)),
            switchRow(icon: "bolt", title: "十殿加速", subtitle: "提升十殿战斗速度", key: "speed_enabled", defaultValue: false, color: Theme.yellowSoft),
            switchRow(icon: "speaker.slash", title: "声音关闭", subtitle: "关闭游戏声音", key: "sound_muted", defaultValue: false, color: Theme.coralSoft),
            switchRow(icon: "eye.slash", title: "隐藏弹窗", subtitle: "隐藏首次登录时的提示弹窗", key: "popup_hidden", defaultValue: false, color: Theme.skySoft)
        ])
        addSection("文件与存储", rows: [
            navigationRow(icon: "folder", title: "存储管理", subtitle: "账号持久化、文件导出与缓存清理", color: Theme.pinkSoft, action: #selector(showStorageManager))
        ])
        addSection("游戏容器", rows: [
            switchRow(icon: "externaldrive", title: "资源缓存", subtitle: "缓存远程游戏资源，加快再次启动", key: "cache_enabled", defaultValue: true, color: Theme.skySoft),
            switchRow(icon: "pause", title: "后台暂停", subtitle: "离开窗口后暂停渲染", key: "pause_background", defaultValue: true, color: Theme.mintSoft)
        ])
        addSection("关于", rows: [
            infoRow(icon: "info.circle", title: "版本信息", subtitle: "v1.2.2 · build 2 · iOS\n1.免费软件，严禁任何形式的倒卖或商业化分发。\n2.用户因个人原因加载第三方脚本、修改程序数据等行为所引发的账号封禁、数据丢失等一切后果，由用户自行承担，均与本软件无关;", color: Theme.palette.orangeSoft)
        ])
    }

    private func addSection(_ title: String, rows: [UIView]) {
        let label = UILabel()
        label.text = title
        label.textColor = Theme.secondaryInk
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.heightAnchor.constraint(equalToConstant: stack.arrangedSubviews.isEmpty ? 38 : 46).isActive = true
        stack.addArrangedSubview(label)

        let group = UIStackView()
        group.axis = .vertical
        group.backgroundColor = Theme.card
        group.rounded(12, border: Theme.line)
        rows.enumerated().forEach { index, row in
            group.addArrangedSubview(row)
            if index < rows.count - 1 {
                let divider = UIView()
                divider.backgroundColor = Theme.line
                divider.heightAnchor.constraint(equalToConstant: 1).isActive = true
                group.addArrangedSubview(divider)
            }
        }
        stack.addArrangedSubview(group)
    }

    private func navigationRow(icon: String, title: String, subtitle: String, color: UIColor, action: Selector) -> UIView {
        let row = baseRow(icon: icon, title: title, subtitle: subtitle, color: color)
        let arrow = UIImageView(image: Theme.symbol("chevron.right", size: 13, weight: .semibold))
        arrow.tintColor = Theme.secondaryInk
        arrow.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(arrow)
        NSLayoutConstraint.activate([
            arrow.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            arrow.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        let tap = UITapGestureRecognizer(target: self, action: action)
        row.addGestureRecognizer(tap)
        return row
    }

    private func switchRow(icon: String, title: String, subtitle: String, key: String, defaultValue: Bool, color: UIColor, enabled: Bool = true) -> UIView {
        let row = baseRow(icon: icon, title: title, subtitle: subtitle, color: color)
        let control = UISwitch()
        control.isOn = preferences.object(forKey: key) == nil ? defaultValue : preferences.bool(forKey: key)
        control.onTintColor = Theme.mint
        control.isEnabled = enabled
        control.alpha = enabled ? 1 : 0.45
        control.translatesAutoresizingMaskIntoConstraints = false
        control.addAction(UIAction { [weak self, weak control] _ in
            guard let toggle = control else { return }
            if key == "sound_muted", !toggle.isOn,
               self?.preferences.bool(forKey: key) == true {
                self?.preferences.set(true, forKey: "sound_restore_pending")
            }
            self?.preferences.set(toggle.isOn, forKey: key)
            if key == "sound_muted" || key == "speed_enabled" || key == "popup_hidden" {
                NotificationCenter.default.post(name: .snowKingScriptsChanged, object: nil)
            }
        }, for: .valueChanged)
        row.addSubview(control)
        NSLayoutConstraint.activate([
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor)
        ])
        return row
    }

    private func infoRow(icon: String, title: String, subtitle: String, color: UIColor) -> UIView {
        baseRow(icon: icon, title: title, subtitle: subtitle, color: color, height: 170)
    }

    private func baseRow(icon: String, title: String, subtitle: String, color: UIColor, height: CGFloat = 72) -> UIView {
        let row = UIView()
        row.heightAnchor.constraint(equalToConstant: height).isActive = true
        let iconBox = UIView()
        iconBox.backgroundColor = color
        iconBox.rounded(9)
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(iconBox)
        let image = UIImageView(image: Theme.symbol(icon, size: 17, weight: .medium))
        image.tintColor = Theme.ink
        image.contentMode = .scaleAspectFit
        image.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(image)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.textColor = Theme.ink
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        let subtitleLabel = UILabel()
        subtitleLabel.text = subtitle
        subtitleLabel.textColor = Theme.secondaryInk
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.numberOfLines = 0
        subtitleLabel.lineBreakMode = .byWordWrapping
        let copy = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        copy.axis = .vertical
        copy.spacing = 3
        copy.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(copy)
        NSLayoutConstraint.activate([
            iconBox.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            iconBox.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            iconBox.widthAnchor.constraint(equalToConstant: 32),
            iconBox.heightAnchor.constraint(equalToConstant: 32),
            image.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            image.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 18),
            image.heightAnchor.constraint(equalToConstant: 18),
            copy.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 12),
            copy.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            copy.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor, constant: -70)
        ])
        return row
    }

    @objc private func openLocalScripts() {
        let controller = LocalScriptsViewController()
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    @objc private func showStorageManager() {
        let store = AccountStore.shared
        let accountSize = ByteCountFormatter.string(fromByteCount: store.storageSize, countStyle: .file)
        let scriptSize = ByteCountFormatter.string(fromByteCount: LocalScriptStore.shared.storageSize, countStyle: .file)
        let exportSize = ByteCountFormatter.string(fromByteCount: GameBridge.exportStorageSize, countStyle: .file)
        let message = "账号：\(store.accounts.count) 个（\(accountSize)）\n本地脚本：\(scriptSize)\n脚本导出：\(exportSize)\n\n账号目录：文件 App / 我的 iPhone / 雪花之王 / SnowKingAccounts\n导出目录：文件 App / 我的 iPhone / 雪花之王 / SnowKingExports"
        let actions = [ThemedSheetAction(title: "清理旧版网页缓存", icon: "trash", background: Theme.coralSoft, destructive: true) { [weak self] in self?.clearWebCache() }]
        present(ThemedActionSheetController(title: "存储管理", message: message, actions: actions), animated: false)
    }

    private func clearWebCache() {
        GameBridge.clearResourceCaches { [weak self] before, after, urlCacheBytes in
            let cleared = max(0, before - after)
            let formatted = ByteCountFormatter.string(fromByteCount: Int64(urlCacheBytes), countStyle: .file)
            SnowLogger.info("Cache", "game cache cleared recordsBefore=\(before) recordsAfter=\(after) urlCache=\(urlCacheBytes)")
            NotificationCenter.default.post(name: .snowKingGameCacheCleared, object: nil)
            let message = "已清理 \(cleared) 条网页缓存记录和 \(formatted) 原生网络缓存。运行中的游戏已重新加载，账号、本地脚本、Cookie 和网页存储未删除。"
            let alert = UIAlertController(title: "游戏缓存已清理", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            self?.present(alert, animated: true)
        }
    }
}

final class LocalScriptsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private var scripts: [LocalScript] = []
    private var searchQuery = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.page
        navigationController?.setNavigationBarHidden(true, animated: false)
        build()
        reload()
    }

    private func build() {
        let header = UIView()
        header.backgroundColor = Theme.card
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)

        let back = UIButton.iconButton(systemName: "chevron.left", tint: Theme.ink, size: 42)
        back.backgroundColor = Theme.controlSoft
        back.accessibilityLabel = "返回"
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(back)

        let title = UILabel()
        title.text = "脚本管理"
        title.textColor = Theme.ink
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)

        let search = UIButton.iconButton(systemName: "magnifyingglass", tint: Theme.ink, size: 40)
        search.backgroundColor = .clear
        search.layer.borderWidth = 0
        search.accessibilityLabel = "搜索脚本"
        search.addTarget(self, action: #selector(searchScripts), for: .touchUpInside)
        search.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(search)

        let banner = UIView()
        banner.backgroundColor = Theme.yellowSoft
        banner.rounded(10)
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)
        let bannerWidth = banner.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -28)
        bannerWidth.priority = .defaultHigh
        let description = UILabel()
        description.text = "导入和管理 .js 脚本"
        description.textColor = Theme.secondaryInk
        description.font = .systemFont(ofSize: 13, weight: .semibold)
        description.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(description)
        let add = UIButton.iconButton(systemName: "plus", tint: Theme.ink, size: 34)
        add.backgroundColor = Theme.mintSoft
        add.layer.borderWidth = 0
        add.accessibilityLabel = "导入 JS 脚本"
        add.addTarget(self, action: #selector(importScript), for: .touchUpInside)
        add.translatesAutoresizingMaskIntoConstraints = false
        banner.addSubview(add)

        tableView.backgroundColor = Theme.page
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(LocalScriptCardCell.self, forCellReuseIdentifier: "LocalScriptCard")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "EmptyScript")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 62),
            back.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            back.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 12),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            search.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
            search.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            banner.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 7),
            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bannerWidth,
            banner.widthAnchor.constraint(lessThanOrEqualToConstant: 720),
            banner.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 14),
            banner.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -14),
            banner.heightAnchor.constraint(equalToConstant: 44),
            description.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: 12),
            description.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            add.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -6),
            add.centerYAnchor.constraint(equalTo: banner.centerYAnchor),
            description.trailingAnchor.constraint(lessThanOrEqualTo: add.leadingAnchor, constant: -8),
            tableView.topAnchor.constraint(equalTo: banner.bottomAnchor, constant: 7),
            tableView.leadingAnchor.constraint(equalTo: banner.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: banner.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    @objc private func close() { dismiss(animated: true) }
    private func reload() {
        let all = LocalScriptStore.shared.scripts
        scripts = searchQuery.isEmpty ? all : all.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        tableView.reloadData()
    }

    @objc private func searchScripts() {
        let alert = UIAlertController(title: "搜索脚本", message: nil, preferredStyle: .alert)
        alert.addTextField { [weak self] field in field.placeholder = "脚本名称"; field.text = self?.searchQuery }
        alert.addAction(UIAlertAction(title: "清除", style: .default) { [weak self] _ in self?.searchQuery = ""; self?.reload() })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "搜索", style: .default) { [weak self, weak alert] _ in
            self?.searchQuery = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self?.reload()
        })
        present(alert, animated: true)
    }

    func numberOfSections(in tableView: UITableView) -> Int { 1 }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(1, scripts.count)
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        "外置脚本"
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        42
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        scripts.isEmpty ? 130 : 84
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard !scripts.isEmpty else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "EmptyScript", for: indexPath)
            var content = cell.defaultContentConfiguration()
            content.text = searchQuery.isEmpty ? "还没有导入脚本" : "没有匹配的脚本"
            content.textProperties.alignment = .center
            content.textProperties.color = Theme.secondaryInk
            cell.contentConfiguration = content
            cell.backgroundColor = Theme.card
            cell.rounded(12, border: Theme.line)
            cell.selectionStyle = .none
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: "LocalScriptCard", for: indexPath) as! LocalScriptCardCell
        let script = scripts[indexPath.row]
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        let state = script.enabled ? "已启用" : "已禁用"
        cell.configureScript(
            title: script.name,
            subtitle: "\(state) · \(script.size / 1024) KB · \(formatter.string(from: script.modifiedAt))",
            enabled: script.enabled,
            onToggle: { [weak self] enabled in self?.setScript(enabled: enabled, script: script) },
            onDelete: { [weak self] in self?.confirmDelete(script) }
        )
        return cell
    }

    private func setScript(enabled: Bool, script: LocalScript) {
        LocalScriptStore.shared.setEnabled(enabled, for: script)
        reload()
    }

    private func confirmDelete(_ script: LocalScript) {
        let alert = UIAlertController(title: "删除脚本", message: script.name, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            try? LocalScriptStore.shared.delete(script)
            self?.reload()
        })
        present(alert, animated: true)
    }

    @objc private func importScript() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType(filenameExtension: "js") ?? .plainText], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard !urls.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var failures: [String] = []
            urls.forEach { url in
                do { try LocalScriptStore.shared.importScript(from: url) }
                catch { failures.append(url.lastPathComponent) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.reload()
                if !failures.isEmpty {
                    let alert = UIAlertController(title: "部分脚本导入失败", message: failures.joined(separator: "\n"), preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "确定", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }
}

#if false
private final class BuiltinScriptsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let categories = ["日常辅助", "十殿", "盐场", "蟠桃"]
    private var scripts = BuiltinScriptStore.scripts

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.page
        navigationController?.setNavigationBarHidden(true, animated: false)

        let header = UIView()
        header.backgroundColor = Theme.card
        header.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(header)
        let back = UIButton.iconButton(systemName: "chevron.left", tint: Theme.ink, size: 42)
        back.backgroundColor = Theme.controlSoft
        back.accessibilityLabel = "返回"
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        back.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(back)
        let title = UILabel()
        title.text = "内置脚本"
        title.textColor = Theme.ink
        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(title)

        tableView.backgroundColor = Theme.page
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.register(BuiltinScriptCardCell.self, forCellReuseIdentifier: "BuiltinScriptCard")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 62),
            back.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            back.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            title.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 12),
            title.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            tableView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            tableView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    @objc private func close() { navigationController?.popViewController(animated: true) }

    func numberOfSections(in tableView: UITableView) -> Int { categories.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        scripts.filter { $0.category == categories[section] }.count
    }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let count = scripts.filter { $0.category == categories[section] }.count
        return count > 0 ? "\(categories[section])  ·  \(count) 个脚本" : nil
    }
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat { 38 }
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat { 84 }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let sectionScripts = scripts.filter { $0.category == categories[indexPath.section] }
        let script = sectionScripts[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "BuiltinScriptCard", for: indexPath) as! BuiltinScriptCardCell
        cell.configure(script: script) { [weak self] enabled in
            BuiltinScriptStore.setEnabled(enabled, for: script)
            self?.scripts = BuiltinScriptStore.scripts
            self?.tableView.reloadData()
        }
        return cell
    }
}

private final class BuiltinScriptCardCell: UITableViewCell {
    private let card = UIView()
    private let iconBox = UIView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let toggle = UISwitch()
    private var onToggle: ((Bool) -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        card.backgroundColor = Theme.card
        card.rounded(12, border: Theme.line)
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        iconBox.backgroundColor = Theme.mintSoft
        iconBox.rounded(9)
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(iconBox)
        let icon = UIImageView(image: Theme.lineIcon("script", size: 20))
        icon.tintColor = Theme.ink
        icon.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(icon)
        titleLabel.textColor = Theme.ink
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.textColor = Theme.secondaryInk
        subtitleLabel.font = .systemFont(ofSize: 11)
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(labels)
        toggle.onTintColor = Theme.mint
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(toggle)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            iconBox.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            iconBox.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconBox.widthAnchor.constraint(equalToConstant: 38),
            iconBox.heightAnchor.constraint(equalToConstant: 38),
            icon.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20),
            labels.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 10),
            labels.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),
            toggle.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            toggle.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(script: BuiltinScript, onToggle: @escaping (Bool) -> Void) {
        titleLabel.text = script.name
        subtitleLabel.text = "\(script.description)  ·  \(script.enabled ? "已启用" : "已禁用") · 内置"
        toggle.isOn = script.enabled
        self.onToggle = onToggle
    }

    @objc private func toggleChanged() { onToggle?(toggle.isOn) }
}
#endif

private final class LocalScriptCardCell: UITableViewCell {
    private let card = UIView()
    private let iconBox = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let toggle = UISwitch()
    private let deleteButton = UIButton(type: .system)
    private var onToggle: ((Bool) -> Void)?
    private var onDelete: (() -> Void)?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        card.backgroundColor = Theme.card
        card.rounded(12, border: Theme.line)
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        iconBox.backgroundColor = Theme.palette.lavenderSoft
        iconBox.rounded(9)
        iconBox.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(iconBox)
        iconView.image = Theme.lineIcon("script", size: 20)
        iconView.tintColor = Theme.ink
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(iconView)
        titleLabel.textColor = Theme.ink
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.textColor = Theme.secondaryInk
        subtitleLabel.font = .systemFont(ofSize: 11)
        let labels = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        labels.axis = .vertical
        labels.spacing = 3
        labels.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(labels)
        toggle.onTintColor = Theme.mint
        toggle.addTarget(self, action: #selector(toggleChanged), for: .valueChanged)
        toggle.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(toggle)
        deleteButton.setImage(Theme.lineIcon("trash", size: 16), for: .normal)
        deleteButton.tintColor = Theme.coral
        deleteButton.backgroundColor = Theme.coralSoft
        deleteButton.rounded(14)
        deleteButton.addTarget(self, action: #selector(deleteTapped), for: .touchUpInside)
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(deleteButton)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            iconBox.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            iconBox.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconBox.widthAnchor.constraint(equalToConstant: 38),
            iconBox.heightAnchor.constraint(equalToConstant: 38),
            iconView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 20),
            iconView.heightAnchor.constraint(equalToConstant: 20),
            labels.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 10),
            labels.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),
            deleteButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
            deleteButton.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 28),
            deleteButton.heightAnchor.constraint(equalToConstant: 28),
            toggle.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -8),
            toggle.centerYAnchor.constraint(equalTo: card.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configureScript(title: String, subtitle: String, enabled: Bool, onToggle: @escaping (Bool) -> Void, onDelete: @escaping () -> Void) {
        titleLabel.text = title
        subtitleLabel.text = subtitle
        toggle.isOn = enabled
        toggle.isHidden = false
        deleteButton.isHidden = false
        self.onToggle = onToggle
        self.onDelete = onDelete
    }

    @objc private func toggleChanged() { onToggle?(toggle.isOn) }
    @objc private func deleteTapped() { onDelete?() }
}
