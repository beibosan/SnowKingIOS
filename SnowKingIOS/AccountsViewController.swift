import UIKit
import UniformTypeIdentifiers

final class AccountsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UIDocumentPickerDelegate {
    var onStartMulti: (([SnowAccount]) -> Void)?
    private let table = UITableView(frame: .zero, style: .plain)
    private let contentGuide = UILayoutGuide()
    private let groupTags = FlowChipsView()
    private let batchButton = UIButton(type: .system)
    private let sortButton = UIButton(type: .system)
    private var accounts: [SnowAccount] = []
    private var searchQuery = ""
    private var selectedGroup = "全部"
    private enum SortDimension: String { case original = "默认", name = "名称", date = "日期", size = "大小" }
    private var sortDimension: SortDimension = .original
    private var sortAscending = true
    private var selectedIDs = Set<UUID>()
    private var isBatchSelecting = false
    private var isExporting = false

    private var filteredAccounts: [SnowAccount] {
        let value = accounts.filter { account in
            let groupMatches = selectedGroup == "全部" || account.group == selectedGroup
            let queryMatches = searchQuery.isEmpty || account.name.localizedCaseInsensitiveContains(searchQuery) || account.group.localizedCaseInsensitiveContains(searchQuery)
            return groupMatches && queryMatches
        }
        let sorted: [SnowAccount]
        switch sortDimension {
        case .original: sorted = value
        case .name: sorted = value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .date: sorted = value.sorted { $0.displayDate < $1.displayDate }
        case .size: sorted = value.sorted { $0.dataSize < $1.dataSize }
        }
        return sortAscending ? sorted : Array(sorted.reversed())
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.page
        build()
        reloadAccounts()
        NotificationCenter.default.addObserver(self, selector: #selector(addAccount), name: .addSnowAccount, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(searchAccounts(_:)), name: .searchSnowAccounts, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); reloadAccounts() }

    private func build() {
        view.addLayoutGuide(contentGuide)
        NSLayoutConstraint.activate([
            contentGuide.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            contentGuide.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -32)
        ])

        let actionRow = UIStackView()
        actionRow.axis = .horizontal
        actionRow.alignment = .center
        actionRow.spacing = 10
        actionRow.distribution = .fillEqually
        actionRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionRow)
        configureAction(batchButton, title: "批量操作", icon: "checklist", background: Theme.palette.orangeSoft, tint: Theme.orange)
        batchButton.addTarget(self, action: #selector(batchAction), for: .touchUpInside)
        configureAction(sortButton, title: "排序", icon: "arrow.up.arrow.down", background: Theme.mintSoft, tint: Theme.mint)
        sortButton.addTarget(self, action: #selector(showSortOptions), for: .touchUpInside)
        batchButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        sortButton.heightAnchor.constraint(equalToConstant: 44).isActive = true
        actionRow.addArrangedSubview(batchButton)
        actionRow.addArrangedSubview(sortButton)

        let groupBar = UIStackView()
        groupBar.axis = .horizontal
        groupBar.alignment = .center
        groupBar.spacing = 6
        groupBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(groupBar)
        let groupTitle = labelButton(title: "账号分组", icon: "group", background: .clear, fontSize: 14)
        groupBar.addArrangedSubview(groupTitle)
        let manage = labelButton(title: "管理分组", icon: "gearshape", background: Theme.palette.lavenderSoft, fontSize: 11)
        manage.addTarget(self, action: #selector(manageGroups), for: .touchUpInside)
        groupBar.addArrangedSubview(manage)
        let create = labelButton(title: "新建分组", icon: "plus", background: Theme.yellowSoft, fontSize: 11)
        create.addTarget(self, action: #selector(createGroup), for: .touchUpInside)
        groupBar.addArrangedSubview(create)
        groupTitle.widthAnchor.constraint(equalToConstant: 108).isActive = true
        manage.widthAnchor.constraint(equalTo: create.widthAnchor).isActive = true
        groupTitle.heightAnchor.constraint(equalToConstant: 44).isActive = true
        manage.heightAnchor.constraint(equalToConstant: 44).isActive = true
        create.heightAnchor.constraint(equalToConstant: 44).isActive = true

        groupTags.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(groupTags)

        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 95
        table.register(AccountCell.self, forCellReuseIdentifier: "AccountCell")
        view.addSubview(table)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
        table.addGestureRecognizer(longPress)

        NSLayoutConstraint.activate([
            actionRow.topAnchor.constraint(equalTo: view.topAnchor),
            actionRow.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            actionRow.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            actionRow.heightAnchor.constraint(equalToConstant: 52),
            groupBar.topAnchor.constraint(equalTo: actionRow.bottomAnchor),
            groupBar.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            groupBar.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            groupBar.heightAnchor.constraint(equalToConstant: 52),
            groupTags.topAnchor.constraint(equalTo: groupBar.bottomAnchor),
            groupTags.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            groupTags.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            table.topAnchor.constraint(equalTo: groupTags.bottomAnchor, constant: 5),
            table.leadingAnchor.constraint(equalTo: contentGuide.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: contentGuide.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func configureAction(_ button: UIButton, title: String, icon: String, background: UIColor, tint: UIColor) {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = Theme.symbol(icon, size: 16, weight: .semibold)
        config.imagePadding = 8
        config.imagePlacement = .leading
        config.titleAlignment = .center
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)
        config.baseForegroundColor = Theme.ink
        config.imageColorTransformer = UIConfigurationColorTransformer { _ in tint }
        config.background.backgroundColor = background
        config.background.cornerRadius = 12
        config.background.strokeColor = Theme.line
        config.background.strokeWidth = 1
        button.configuration = config
        button.tintColor = tint
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
    }

    private func labelButton(title: String, icon: String, background: UIColor, fontSize: CGFloat) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = icon == "group" ? Theme.lineIcon("group", size: 14) : Theme.symbol(icon, size: 14, weight: .semibold)
        config.imagePadding = 5
        config.imagePlacement = .leading
        config.titleAlignment = .center
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8)
        config.baseForegroundColor = Theme.ink
        config.background.backgroundColor = background
        config.background.cornerRadius = 17
        let button = UIButton(configuration: config)
        button.titleLabel?.font = .systemFont(ofSize: fontSize, weight: .semibold)
        return button
    }

    private func reloadAccounts() {
        accounts = AccountStore.shared.accounts
        renderGroupTags()
        if isViewLoaded { table.reloadData() }
    }

    private func renderGroupTags() {
        groupTags.subviews.forEach { $0.removeFromSuperview() }
        let groups = ["全部", "未分组"] + GroupStore.shared.groups
        groups.forEach { name in
            let button = UIButton(type: .system)
            button.setTitle(name, for: .normal)
            button.setTitleColor(name == selectedGroup ? .white : Theme.ink, for: .normal)
            button.backgroundColor = name == selectedGroup ? Theme.pink : Theme.card
            button.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 13, bottom: 0, right: 13)
            button.rounded(16, border: Theme.line)
            button.addAction(UIAction { [weak self] _ in self?.selectedGroup = name; self?.renderGroupTags(); self?.table.reloadData() }, for: .touchUpInside)
            groupTags.addSubview(button)
        }
        groupTags.invalidateIntrinsicContentSize()
        groupTags.setNeedsLayout()
    }

    @objc private func searchAccounts(_ notification: Notification) {
        searchQuery = (notification.object as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        table.reloadData()
    }

    @objc private func showSortOptions() {
        var actions: [ThemedSheetAction] = []
        [SortDimension.original, .name, .date, .size].forEach { dimension in
            [true, false].forEach { ascending in
                let selected = dimension == sortDimension && ascending == sortAscending
                let direction = ascending ? "升序" : "降序"
                actions.append(ThemedSheetAction(title: (selected ? "✓ " : "") + "\(dimension.rawValue) · \(direction)", icon: ascending ? "arrow.up" : "arrow.down", background: selected ? Theme.pinkSoft : Theme.controlSoft) { [weak self] in
                    self?.sortDimension = dimension
                    self?.sortAscending = ascending
                    self?.updateSortTitle()
                    self?.table.reloadData()
                })
            }
        }
        present(ThemedActionSheetController(title: "排序方式", message: "当前：\(sortDimension.rawValue) · \(sortAscending ? "升序" : "降序")", actions: actions), animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateSortTitle()
        updateBatchTitle()
    }

    @objc private func batchAction() {
        var actions: [ThemedSheetAction] = []
        if !isBatchSelecting {
            actions.append(ThemedSheetAction(title: "开始选择账号", icon: "checklist", background: Theme.skySoft) { [weak self] in
                self?.isBatchSelecting = true
                self?.selectedIDs.removeAll()
                self?.table.reloadData()
                self?.updateBatchTitle()
            })
        }
        actions.append(ThemedSheetAction(title: "全选当前列表", icon: "checkmark.circle", background: Theme.skySoft) { [weak self] in
            guard let self else { return }
            self.isBatchSelecting = true
            self.selectedIDs = Set(self.filteredAccounts.map(\.id))
            self.table.reloadData()
            self.updateBatchTitle()
        })
        actions.append(ThemedSheetAction(title: "批量启动", icon: "arrow.up.right.square", background: Theme.mintSoft) { [weak self] in self?.startSelectedAccounts() })
        actions.append(ThemedSheetAction(title: "批量关闭", icon: "stop", background: Theme.coralSoft) { [weak self] in self?.closeSelectedAccounts() })
        actions.append(ThemedSheetAction(title: "分配到分组", icon: "person.2", background: Theme.palette.lavenderSoft) { [weak self] in self?.assignSelectedGroup() })
        actions.append(ThemedSheetAction(title: "批量删除", icon: "trash", background: Theme.pinkSoft, destructive: true) { [weak self] in self?.confirmBatchDelete() })
        if isBatchSelecting {
            actions.append(ThemedSheetAction(title: "退出批量模式", icon: "xmark", background: Theme.controlSoft) { [weak self] in self?.exitBatchMode() })
        }
        present(ThemedActionSheetController(title: "批量操作", message: "已选 \(selectedIDs.count) / \(accounts.count) 个账号", actions: actions), animated: false)
    }

    private func startSelectedAccounts() {
        guard !selectedIDs.isEmpty else { presentMessage(title: "批量启动", message: "请先点“开始选择账号”或“全选当前列表”。"); return }
        let selected = AccountStore.shared.accounts.filter { selectedIDs.contains($0.id) }
        guard selected.allSatisfy({ !($0.binData ?? "").isEmpty }) else {
            presentMessage(title: "批量启动失败", message: "选中的账号中包含没有 BIN/JSON 登录数据的账号。")
            return
        }
        AccountStore.shared.updateStatus(ids: selectedIDs, status: "运行中", operation: "批量启动")
        exitBatchMode(reload: false)
        reloadAccounts()
        onStartMulti?(selected)
    }

    private func closeSelectedAccounts() {
        guard !selectedIDs.isEmpty else { presentMessage(title: "批量关闭", message: "请先选择账号。"); return }
        NotificationCenter.default.post(name: .closeSnowAccounts, object: selectedIDs)
        AccountStore.shared.updateStatus(ids: selectedIDs, status: "已关闭", operation: "批量关闭")
        exitBatchMode(reload: false)
        reloadAccounts()
    }

    private func assignSelectedGroup() {
        guard !selectedIDs.isEmpty else { presentMessage(title: "分配到分组", message: "请先选择账号。"); return }
        let actions = (["未分组"] + GroupStore.shared.groups).map { group in
            ThemedSheetAction(title: group, icon: "folder", background: Theme.palette.lavenderSoft) { [weak self] in
                guard let self else { return }
                var value = AccountStore.shared.accounts
                for index in value.indices where self.selectedIDs.contains(value[index].id) { value[index].group = group }
                AccountStore.shared.replace(value)
                self.exitBatchMode(reload: false)
                self.reloadAccounts()
            }
        }
        present(ThemedActionSheetController(title: "分配到分组", message: "已选 \(selectedIDs.count) 个账号", actions: actions), animated: false)
    }

    private func confirmBatchDelete() {
        guard !selectedIDs.isEmpty else { presentMessage(title: "批量删除", message: "请先选择账号。"); return }
        let alert = UIAlertController(title: "批量删除", message: "确定删除选中的 \(selectedIDs.count) 个本地账号？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            guard let self else { return }
            var value = AccountStore.shared.accounts
            value.removeAll { self.selectedIDs.contains($0.id) }
            AccountStore.shared.replace(value)
            self.exitBatchMode(reload: false)
            self.reloadAccounts()
        })
        present(alert, animated: true)
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: table)
        guard let indexPath = table.indexPathForRow(at: point) else { return }
        isBatchSelecting = true
        selectedIDs.insert(filteredAccounts[indexPath.row].id)
        table.reloadData()
        updateBatchTitle()
    }

    private func updateBatchTitle() {
        batchButton.configuration?.title = isBatchSelecting ? "已选 \(selectedIDs.count) 个" : "批量操作"
    }

    private func exitBatchMode(reload: Bool = true) {
        isBatchSelecting = false
        selectedIDs.removeAll()
        updateBatchTitle()
        if reload { table.reloadData() }
    }

    private func updateSortTitle() {
        let arrow = sortAscending ? "↑" : "↓"
        sortButton.configuration?.title = sortDimension == .original ? "排序" : "\(sortDimension.rawValue) \(arrow)"
    }

    @objc private func createGroup() {
        let alert = UIAlertController(title: "新建分组", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "分组名称" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "创建", style: .default) { [weak self, weak alert] _ in
            guard let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
            guard GroupStore.shared.add(name) else {
                self?.presentMessage(title: "无法创建分组", message: "分组名称为空、重复或使用了保留名称。")
                return
            }
            self?.selectedGroup = name
            self?.reloadAccounts()
        })
        present(alert, animated: true)
    }

    @objc private func manageGroups() {
        let controller = GroupManagerViewController()
        controller.onChange = { [weak self] in self?.reloadAccounts() }
        present(UINavigationController(rootViewController: controller), animated: true)
    }

    @objc private func addAccount() {
        let actions = [
            ThemedSheetAction(title: "导入 BIN/JSON 文件", icon: "doc.badge.plus", background: Theme.mintSoft) { [weak self] in self?.showImportPicker() },
            ThemedSheetAction(title: "微信扫码导入", icon: "qrcode", background: Theme.skySoft) { [weak self] in self?.showWechatScanner() },
            ThemedSheetAction(title: "仅添加名称", icon: "person.badge.plus", background: Theme.skySoft) { [weak self] in self?.showNamePrompt() }
        ]
        present(ThemedActionSheetController(title: "新增或导入账号", actions: actions), animated: false)
    }

    private func showImportPicker() {
        isExporting = false
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType(filenameExtension: "bin") ?? .data, .json, .data], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }

    private func showNamePrompt() {
        let alert = UIAlertController(title: "添加本地账号", message: "此账号不包含登录会话。", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "账号名称" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return }
            AccountStore.shared.add(name: name)
            self?.reloadAccounts()
        })
        present(alert, animated: true)
    }

    private func showWechatScanner() {
        let controller = WeChatScannerViewController()
        controller.onSaved = { [weak self] in self?.reloadAccounts() }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        present(navigation, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if isExporting { isExporting = false; return }
        var failures: [String] = []
        urls.forEach { url in
            do {
                let fileExtension = url.pathExtension.lowercased()
                guard fileExtension == "bin" || fileExtension == "json" else { throw CocoaError(.fileReadUnsupportedScheme) }
                let data = try Data(contentsOf: url)
                guard !data.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
                AccountStore.shared.addImported(name: url.deletingPathExtension().lastPathComponent, data: data, fileName: url.lastPathComponent)
            } catch { failures.append(url.lastPathComponent) }
        }
        reloadAccounts()
        if !failures.isEmpty { presentMessage(title: "部分文件导入失败", message: failures.joined(separator: "\n")) }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { isExporting = false }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { filteredAccounts.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "AccountCell", for: indexPath) as! AccountCell
        let account = filteredAccounts[indexPath.row]
        cell.configure(account, selected: selectedIDs.contains(account.id))
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let account = filteredAccounts[indexPath.row]
        if isBatchSelecting {
            if selectedIDs.contains(account.id) { selectedIDs.remove(account.id) } else { selectedIDs.insert(account.id) }
            table.reloadData()
            updateBatchTitle()
            return
        }
        showAccountActions(account)
    }

    private func showAccountActions(_ account: SnowAccount) {
        let sheet = AccountActionsViewController(account: account, actions: [
            .init(title: "启动账号", icon: "arrow.up.right.square", background: Theme.mintSoft) { [weak self] in self?.launch(account) },
            .init(title: "关闭账号", icon: "stop", background: Theme.coralSoft) { [weak self] in
                AccountStore.shared.updateStatus(ids: [account.id], status: "已关闭", operation: "关闭窗口")
                self?.reloadAccounts()
            },
            .init(title: "修改名称", icon: "pencil", background: Theme.skySoft) { [weak self] in self?.rename(account) },
            .init(title: "分配账号分组", icon: "person.2", background: Theme.palette.lavenderSoft) { [weak self] in self?.moveGroup(account) },
            .init(title: "导出账号 .bin 文件", icon: "arrow.down.to.line", background: Theme.yellowSoft) { [weak self] in self?.export(account) },
            .init(title: "删除账号", icon: "trash", background: Theme.pinkSoft) { [weak self] in self?.confirmDelete(account) }
        ])
        sheet.modalPresentationStyle = .overFullScreen
        sheet.modalTransitionStyle = .crossDissolve
        present(sheet, animated: false)
    }

    private func confirmDelete(_ account: SnowAccount) {
        let alert = UIAlertController(title: "删除账号", message: "将删除本地账号“\(account.name)”，此操作不可恢复。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            var value = AccountStore.shared.accounts
            value.removeAll { $0.id == account.id }
            AccountStore.shared.replace(value)
            self?.reloadAccounts()
        })
        present(alert, animated: true)
    }

    private func launch(_ account: SnowAccount) {
        guard !(account.binData ?? "").isEmpty else {
            presentMessage(title: "无法启动账号", message: "该账号只有名称，没有可用的 BIN/JSON 登录数据。")
            return
        }
        AccountStore.shared.updateStatus(ids: [account.id], status: "运行中", operation: "启动游戏")
        let game = GameViewController(account: account)
        game.modalPresentationStyle = .fullScreen
        present(game, animated: true)
    }

    private func export(_ account: SnowAccount) {
        let sourceExtension = account.sourceFileName.map { URL(fileURLWithPath: $0).pathExtension.lowercased() }
        let exportAsBIN = sourceExtension == "bin"
        let data = exportAsBIN
            ? (Data(base64Encoded: account.binData ?? "") ?? Data())
            : ((try? JSONEncoder().encode(account)) ?? Data())
        guard !data.isEmpty else { presentMessage(title: "导出失败", message: "该账号没有可导出的本地数据。"); return }
        let rawName = exportAsBIN ? (account.sourceFileName ?? "\(account.name).bin") : "\(account.name).json"
        let safeName = rawName.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        do {
            try data.write(to: url, options: .atomic)
            let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
            picker.delegate = self
            isExporting = true
            present(picker, animated: true)
        } catch { presentMessage(title: "导出失败", message: error.localizedDescription) }
    }

    private func rename(_ account: SnowAccount) {
        let alert = UIAlertController(title: "修改名称", message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = account.name }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let name = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
            AccountStore.shared.update(id: account.id, name: name)
            self?.reloadAccounts()
        })
        present(alert, animated: true)
    }

    private func moveGroup(_ account: SnowAccount) {
        let groups = ["未分组"] + GroupStore.shared.groups
        let actions = groups.map { group in
            ThemedSheetAction(title: (group == account.group ? "✓ " : "") + group, icon: "folder", background: group == account.group ? Theme.pinkSoft : Theme.palette.lavenderSoft) { [weak self] in
                AccountStore.shared.update(id: account.id, group: group)
                self?.reloadAccounts()
            }
        }
        present(ThemedActionSheetController(title: "分配账号分组", message: account.name, actions: actions), animated: false)
    }

    private func presentMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    deinit { NotificationCenter.default.removeObserver(self) }
}

private struct AccountSheetAction {
    let title: String
    let icon: String
    let background: UIColor
    let handler: () -> Void
}

private final class AccountActionsViewController: UIViewController {
    private let account: SnowAccount
    private let actions: [AccountSheetAction]
    private let panel = UIView()

    init(account: SnowAccount, actions: [AccountSheetAction]) {
        self.account = account
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        let dim = UIButton(type: .custom)
        dim.backgroundColor = UIColor(red: 20 / 255, green: 32 / 255, blue: 24 / 255, alpha: 0.42)
        dim.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        dim.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dim)

        panel.backgroundColor = Theme.card
        panel.rounded(24)
        panel.transform = CGAffineTransform(translationX: 0, y: 700)
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)

        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)

        let handleHolder = UIView()
        handleHolder.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let handle = UIView()
        handle.backgroundColor = Theme.ink
        handle.rounded(2.5)
        handle.translatesAutoresizingMaskIntoConstraints = false
        handleHolder.addSubview(handle)
        NSLayoutConstraint.activate([
            handle.centerXAnchor.constraint(equalTo: handleHolder.centerXAnchor),
            handle.centerYAnchor.constraint(equalTo: handleHolder.centerYAnchor),
            handle.widthAnchor.constraint(equalToConstant: 46),
            handle.heightAnchor.constraint(equalToConstant: 5)
        ])
        stack.addArrangedSubview(handleHolder)
        stack.addArrangedSubview(makeHeader())

        actions.enumerated().forEach { index, action in
            let row = makeActionRow(action)
            row.heightAnchor.constraint(equalToConstant: 56).isActive = true
            stack.addArrangedSubview(row)
            if index < actions.count - 1 { stack.setCustomSpacing(5, after: row) }
        }
        let footer = UIView()
        footer.heightAnchor.constraint(equalToConstant: 18).isActive = true
        stack.addArrangedSubview(footer)

        let equalWidth = panel.widthAnchor.constraint(equalTo: view.widthAnchor)
        equalWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            dim.topAnchor.constraint(equalTo: view.topAnchor),
            dim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            panel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            panel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor),
            panel.widthAnchor.constraint(lessThanOrEqualToConstant: 640),
            equalWidth,
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: panel.topAnchor),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: panel.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        panel.transform = CGAffineTransform(translationX: 0, y: panel.bounds.height)
        view.layoutIfNeeded()
        UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut]) {
            self.panel.transform = .identity
        }
    }

    private func makeHeader() -> UIView {
        let header = UIView()
        header.heightAnchor.constraint(equalToConstant: 58).isActive = true
        let avatar = UILabel()
        avatar.text = String(account.name.prefix(1))
        avatar.textAlignment = .center
        avatar.font = .systemFont(ofSize: 14, weight: .bold)
        let colors = [Theme.pink, Theme.sky, Theme.mint, Theme.orange, Theme.lavender, Theme.coral]
        let color = colors[Int(UInt(bitPattern: account.id.hashValue) % UInt(colors.count))]
        avatar.textColor = color
        avatar.backgroundColor = color.withAlphaComponent(0.16)
        avatar.rounded(10)
        avatar.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(avatar)

        let name = UILabel()
        name.text = account.name
        name.textColor = Theme.ink
        name.font = .systemFont(ofSize: 15, weight: .bold)
        let detail = UILabel()
        detail.text = "\(account.sourceFileName ?? account.name + ".bin") · \(account.displayStatus)"
        detail.textColor = Theme.secondaryInk
        detail.font = .systemFont(ofSize: 11, weight: .semibold)
        detail.lineBreakMode = .byTruncatingMiddle
        let copy = UIStackView(arrangedSubviews: [name, detail])
        copy.axis = .vertical
        copy.spacing = 3
        copy.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(copy)
        NSLayoutConstraint.activate([
            avatar.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 4),
            avatar.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 38),
            avatar.heightAnchor.constraint(equalToConstant: 38),
            copy.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            copy.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -4),
            copy.centerYAnchor.constraint(equalTo: header.centerYAnchor)
        ])
        return header
    }

    private func makeActionRow(_ action: AccountSheetAction) -> UIButton {
        var title = AttributedString(action.title)
        title.font = .systemFont(ofSize: 14, weight: .bold)
        var configuration = UIButton.Configuration.plain()
        configuration.attributedTitle = title
        configuration.image = Theme.symbol(action.icon, size: 19, weight: .semibold)
        configuration.imagePlacement = .leading
        configuration.imagePadding = 12
        configuration.baseForegroundColor = Theme.ink
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 44)
        configuration.background.backgroundColor = action.background
        configuration.background.cornerRadius = 12
        let button = UIButton(configuration: configuration)
        button.contentHorizontalAlignment = .leading
        let arrow = UIImageView(image: Theme.symbol("chevron.right", size: 15, weight: .bold))
        arrow.tintColor = Theme.ink
        arrow.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(arrow)
        NSLayoutConstraint.activate([
            arrow.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -14),
            arrow.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        button.addAction(UIAction { [weak self] _ in self?.close(then: action.handler) }, for: .touchUpInside)
        return button
    }

    @objc private func cancel() { close() }

    private func close(then completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.2, animations: {
            self.panel.transform = CGAffineTransform(translationX: 0, y: self.panel.bounds.height)
            self.view.backgroundColor = .clear
        }) { _ in
            self.dismiss(animated: false, completion: completion)
        }
    }
}

final class GroupManagerViewController: UITableViewController {
    var onChange: (() -> Void)?
    private var groups: [String] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "管理分组"
        view.backgroundColor = Theme.page
        tableView.backgroundColor = Theme.page
        tableView.rowHeight = 64
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Group")
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addGroup))
        reload()
    }

    @objc private func close() { dismiss(animated: true) }
    private func reload() { groups = GroupStore.shared.groups; tableView.reloadData(); onChange?() }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { groups.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Group", for: indexPath)
        var content = cell.defaultContentConfiguration()
        let group = groups[indexPath.row]
        content.image = Theme.symbol("folder", size: 17, weight: .medium)
        content.imageProperties.tintColor = Theme.ink
        content.text = group
        content.secondaryText = "\(GroupStore.shared.count(in: group)) 个账号"
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let controller = GroupMembersViewController(group: groups[indexPath.row])
        controller.onChange = { [weak self] in self?.reload() }
        navigationController?.pushViewController(controller, animated: true)
    }

    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let group = groups[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, done in
            self?.confirmDelete(group, completion: done)
        }
        let rename = UIContextualAction(style: .normal, title: "改名") { [weak self] _, _, done in
            self?.promptRename(group, completion: done)
        }
        rename.backgroundColor = Theme.mint
        return UISwipeActionsConfiguration(actions: [delete, rename])
    }

    @objc private func addGroup() { prompt(title: "新建分组", current: nil) }
    private func promptRename(_ group: String, completion: @escaping (Bool) -> Void) { prompt(title: "修改分组名称", current: group, completion: completion) }

    private func prompt(title: String, current: String?, completion: ((Bool) -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { $0.text = current; $0.placeholder = "分组名称" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion?(false) })
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            let value = alert?.textFields?.first?.text ?? ""
            let changed = current.map { GroupStore.shared.rename($0, to: value) } ?? GroupStore.shared.add(value)
            if changed { self?.reload() }
            completion?(changed)
        })
        present(alert, animated: true)
    }

    private func confirmDelete(_ group: String, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: "删除分组", message: "“\(group)”中的账号将移到未分组。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            GroupStore.shared.delete(group)
            self?.reload()
            completion(true)
        })
        present(alert, animated: true)
    }
}

final class GroupMembersViewController: UITableViewController {
    var onChange: (() -> Void)?
    private let group: String
    private var accounts: [SnowAccount] = []

    init(group: String) { self.group = group; super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = group
        view.backgroundColor = Theme.page
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Member")
        accounts = AccountStore.shared.accounts
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { accounts.count }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Member", for: indexPath)
        var content = cell.defaultContentConfiguration()
        let account = accounts[indexPath.row]
        content.text = account.name
        content.secondaryText = account.group == "未分组" ? "未分组" : account.group
        content.image = Theme.symbol("person.crop.circle", size: 17, weight: .medium)
        cell.contentConfiguration = content
        cell.accessoryType = account.group == group ? .checkmark : .none
        cell.tintColor = Theme.mint
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let account = accounts[indexPath.row]
        GroupStore.shared.setMembership(accountID: account.id, group: group, included: account.group != group)
        accounts = AccountStore.shared.accounts
        tableView.reloadRows(at: [indexPath], with: .automatic)
        onChange?()
    }
}

private final class FlowChipsView: UIView {
    private let itemHeight: CGFloat = 32
    private let horizontalSpacing: CGFloat = 7
    private let verticalSpacing: CGFloat = 7
    private var measuredHeight: CGFloat = 32

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: measuredHeight)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        var x: CGFloat = 0
        var y: CGFloat = 0
        for item in subviews {
            let fitting = item.sizeThatFits(CGSize(width: bounds.width, height: itemHeight))
            let width = min(bounds.width, max(44, ceil(fitting.width)))
            if x > 0, x + width > bounds.width {
                x = 0
                y += itemHeight + verticalSpacing
            }
            item.frame = CGRect(x: x, y: y, width: width, height: itemHeight)
            x += width + horizontalSpacing
        }
        let height = subviews.isEmpty ? 0 : y + itemHeight
        if abs(height - measuredHeight) > 0.5 {
            measuredHeight = height
            invalidateIntrinsicContentSize()
        }
    }
}

final class AccountCell: UITableViewCell {
    private let card = UIView()
    private let avatar = UILabel()
    private let name = UILabel()
    private let status = UILabel()
    private let path = UILabel()
    private let time = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        card.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(card)
        avatar.textAlignment = .center
        avatar.font = .systemFont(ofSize: 15, weight: .bold)
        avatar.rounded(12)
        name.font = .systemFont(ofSize: 15, weight: .bold)
        name.textColor = Theme.ink
        status.font = .systemFont(ofSize: 10, weight: .bold)
        status.textAlignment = .center
        status.textColor = Theme.statusIdle
        status.backgroundColor = Theme.skySoft
        status.rounded(11)
        path.font = .systemFont(ofSize: 11)
        path.textColor = Theme.secondaryInk
        path.lineBreakMode = .byTruncatingMiddle
        time.font = .systemFont(ofSize: 11)
        time.textColor = Theme.secondaryInk
        [avatar, name, status, path, time].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; card.addSubview($0) }
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            card.heightAnchor.constraint(equalToConstant: 84),
            avatar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            avatar.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            avatar.widthAnchor.constraint(equalToConstant: 50),
            avatar.heightAnchor.constraint(equalToConstant: 50),
            name.leadingAnchor.constraint(equalTo: avatar.trailingAnchor, constant: 12),
            name.topAnchor.constraint(equalTo: card.topAnchor, constant: 15),
            status.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 7),
            status.centerYAnchor.constraint(equalTo: name.centerYAnchor),
            status.widthAnchor.constraint(equalToConstant: 52),
            status.heightAnchor.constraint(equalToConstant: 22),
            status.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -14),
            path.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            path.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 8),
            path.trailingAnchor.constraint(lessThanOrEqualTo: time.leadingAnchor, constant: -8),
            time.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            time.centerYAnchor.constraint(equalTo: path.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ account: SnowAccount, selected: Bool) {
        card.backgroundColor = selected ? Theme.pinkSoft : Theme.card
        card.rounded(12, border: Theme.line)
        avatar.text = String(account.name.prefix(2))
        let colors = [Theme.pink, Theme.sky, Theme.mint, Theme.orange, Theme.lavender, Theme.coral]
        let color = colors[Int(UInt(bitPattern: account.id.hashValue) % UInt(colors.count))]
        avatar.textColor = color
        avatar.backgroundColor = color.withAlphaComponent(0.16)
        name.text = account.name
        switch account.displayStatus {
        case "运行中": status.textColor = Theme.statusRunning; status.backgroundColor = Theme.mintSoft
        case "已关闭": status.textColor = Theme.statusClosed; status.backgroundColor = Theme.coralSoft
        default: status.textColor = Theme.statusIdle; status.backgroundColor = Theme.skySoft
        }
        status.attributedText = Self.iconText(
            systemName: "circle.fill",
            text: account.displayStatus,
            color: status.textColor,
            size: 7,
            font: .systemFont(ofSize: 10, weight: .bold)
        )
        path.attributedText = Self.iconText(
            systemName: "doc",
            text: account.sourceFileName ?? "\(account.name).bin",
            color: Theme.secondaryInk,
            size: 10,
            font: .systemFont(ofSize: 11)
        )
        time.text = Self.relative(account.importedAt)
    }

    private static func iconText(systemName: String, text: String, color: UIColor, size: CGFloat, font: UIFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        if let image = Theme.symbol(systemName, size: size, weight: .semibold)?.withTintColor(color, renderingMode: .alwaysOriginal) {
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = CGRect(x: 0, y: -1, width: size, height: size)
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: " "))
        }
        result.append(NSAttributedString(string: text, attributes: [.foregroundColor: color, .font: font]))
        return result
    }

    private static func relative(_ date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
