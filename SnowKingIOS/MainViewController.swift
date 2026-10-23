import UIKit

final class MainViewController: UIViewController, UITextFieldDelegate {
    private let content = UIView()
    private let headerView = UIView()
    private let titleLabel = UILabel()
    private let searchField = UITextField()
    private let addButton = UIButton.iconButton(systemName: "plus", tint: Theme.addAccent, size: 42)
    private let paletteButton = UIButton.iconButton(systemName: "paintpalette", tint: Theme.ink, size: 42)
    private let nav = UIStackView()
    private var headerHeightConstraint: NSLayoutConstraint!
    private var navHeightConstraint: NSLayoutConstraint!
    private var currentChild: UIViewController?
    private var selected = 0
    private var announcementPresented = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.page
        buildShell()
        show(page: 0)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !announcementPresented else { return }
        announcementPresented = true
        presentWeeklyAnnouncementIfNeeded()
    }

    private func presentWeeklyAnnouncementIfNeeded() {
        let calendar = Calendar(identifier: .iso8601)
        let now = Date()
        let marker = "\(calendar.component(.yearForWeekOfYear, from: now))-\(calendar.component(.weekOfYear, from: now))"
        guard UserDefaults.standard.string(forKey: "snowking.announcement.dismissed-week") != marker else { return }

        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)
        let imageView = UIImageView(image: UIImage(named: "Announcement"))
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        alert.view.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: alert.view.topAnchor, constant: 20),
            imageView.leadingAnchor.constraint(equalTo: alert.view.leadingAnchor, constant: 12),
            imageView.trailingAnchor.constraint(equalTo: alert.view.trailingAnchor, constant: -12),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor)
        ])
        alert.addAction(UIAlertAction(title: "本周不再提醒", style: .default) { _ in
            UserDefaults.standard.set(marker, forKey: "snowking.announcement.dismissed-week")
        })
        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
        present(alert, animated: true)
    }

    override var shouldAutorotate: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let headerHeight: CGFloat = selected == 1 || selected == 2 ? 0 : 62
        let navHeight: CGFloat = 58
        if headerHeightConstraint.constant != headerHeight { headerHeightConstraint.constant = headerHeight }
        headerView.isHidden = headerHeight == 0
        if navHeightConstraint.constant != navHeight { navHeightConstraint.constant = navHeight }
        nav.directionalLayoutMargins = .zero
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        nav.arrangedSubviews.compactMap { $0 as? NavButton }.forEach { $0.setRegularLayout(false) }
    }

    private func buildShell() {
        let top = headerView
        top.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(top)
        headerHeightConstraint = top.heightAnchor.constraint(equalToConstant: 62)
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            top.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            top.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -32),
            headerHeightConstraint
        ])

        titleLabel.text = "雪花之王"
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = Theme.ink
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        top.addSubview(titleLabel)

        let searchBox = UIView()
        searchBox.backgroundColor = Theme.field
        searchBox.rounded(20, border: Theme.line)
        searchBox.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchBox.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        searchBox.translatesAutoresizingMaskIntoConstraints = false
        top.addSubview(searchBox)
        let searchIcon = UIImageView(image: Theme.symbol("magnifyingglass", size: 14, weight: .medium))
        searchIcon.tintColor = Theme.secondaryInk
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchBox.addSubview(searchIcon)
        searchField.placeholder = "搜索..."
        searchField.font = .systemFont(ofSize: 12)
        searchField.textColor = Theme.ink
        searchField.returnKeyType = .search
        searchField.delegate = self
        searchField.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchBox.addSubview(searchField)

        addButton.accessibilityLabel = "添加账号"
        addButton.backgroundColor = Theme.mintSoft
        addButton.addTarget(self, action: #selector(addAccount), for: .touchUpInside)
        paletteButton.accessibilityLabel = "切换主题"
        paletteButton.backgroundColor = Theme.palette.lavenderSoft
        paletteButton.addTarget(self, action: #selector(toggleTheme), for: .touchUpInside)
        let actions = UIStackView(arrangedSubviews: [addButton, paletteButton])
        actions.spacing = 7
        actions.translatesAutoresizingMaskIntoConstraints = false
        top.addSubview(actions)
        let searchMinWidth = searchBox.widthAnchor.constraint(greaterThanOrEqualToConstant: 120)
        searchMinWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: top.leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            searchBox.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 10),
            searchBox.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            searchBox.heightAnchor.constraint(equalToConstant: 38),
            searchMinWidth,
            searchBox.trailingAnchor.constraint(equalTo: actions.leadingAnchor, constant: -8),
            actions.trailingAnchor.constraint(equalTo: top.trailingAnchor),
            actions.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            searchIcon.leadingAnchor.constraint(equalTo: searchBox.leadingAnchor, constant: 10),
            searchIcon.centerYAnchor.constraint(equalTo: searchBox.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 14),
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 6),
            searchField.trailingAnchor.constraint(equalTo: searchBox.trailingAnchor, constant: -8),
            searchField.topAnchor.constraint(equalTo: searchBox.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: searchBox.bottomAnchor)
        ])

        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        nav.axis = .horizontal
        nav.distribution = .fillEqually
        nav.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(nav)
        nav.isLayoutMarginsRelativeArrangement = true
        navHeightConstraint = nav.heightAnchor.constraint(equalToConstant: 58)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: top.bottomAnchor),
            content.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            content.widthAnchor.constraint(equalTo: view.widthAnchor),
            content.bottomAnchor.constraint(equalTo: nav.topAnchor),
            nav.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            nav.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            nav.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            navHeightConstraint
        ])

        let items = [
            ("账号", "person"),
            ("横向多开", "rectangle.split.2x1"),
            ("纵向多开", "rectangle.split.1x2"),
            ("设置", "gearshape")
        ]
        items.enumerated().forEach { index, item in
            let button = NavButton(title: item.0, systemName: item.1)
            button.tag = index
            button.addTarget(self, action: #selector(selectPage(_:)), for: .touchUpInside)
            nav.addArrangedSubview(button)
        }
    }

    private func show(page: Int, multiAccounts: [SnowAccount]? = nil) {
        selected = page
        let hidesHeader = page == 1 || page == 2
        headerView.isHidden = hidesHeader
        headerHeightConstraint.constant = hidesHeader ? 0 : 62
        let titles = ["雪花之王", "横向多开", "纵向多开", "设置"]
        titleLabel.text = titles[page]
        searchField.superview?.isHidden = page != 0
        addButton.isHidden = page != 0

        currentChild?.willMove(toParent: nil)
        currentChild?.view.removeFromSuperview()
        currentChild?.removeFromParent()

        let controller: UIViewController
        switch page {
        case 0:
            let accountController = AccountsViewController()
            accountController.onStartMulti = { [weak self] accounts in self?.show(page: 1, multiAccounts: accounts) }
            controller = accountController
        case 1:
            let multi = MultiViewController(vertical: false, accounts: multiAccounts ?? [])
            multi.onClose = { [weak self] in self?.show(page: 0) }
            controller = multi
        case 2:
            let multi = MultiViewController(vertical: true, accounts: multiAccounts ?? [])
            multi.onClose = { [weak self] in self?.show(page: 0) }
            controller = multi
        default: controller = SettingsViewController()
        }
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(controller.view)
        controller.didMove(toParent: self)
        currentChild = controller
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: content.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        nav.arrangedSubviews.compactMap { $0 as? NavButton }.forEach { $0.setSelected($0.tag == page) }
    }

    @objc private func selectPage(_ sender: UIButton) {
        guard sender.tag == 1 || sender.tag == 2 else { show(page: sender.tag); return }
        let accounts = AccountStore.shared.accounts.filter { !(($0.binData ?? "").isEmpty) }
        guard !accounts.isEmpty else {
            let alert = UIAlertController(title: "选择多开账号", message: "请先导入 BIN/JSON 账号。", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "确定", style: .default))
            present(alert, animated: true)
            return
        }
        let picker = MultiAccountPickerViewController(accounts: accounts, vertical: sender.tag == 2)
        picker.onStart = { [weak self] selectedAccounts in
            self?.dismiss(animated: true) { self?.show(page: sender.tag, multiAccounts: selectedAccounts) }
        }
        present(UINavigationController(rootViewController: picker), animated: true)
    }
    @objc private func addAccount() { NotificationCenter.default.post(name: .addSnowAccount, object: nil) }
    @objc private func searchChanged() { NotificationCenter.default.post(name: .searchSnowAccounts, object: searchField.text ?? "") }

    @objc private func toggleTheme() {
        let backgrounds = [Theme.pinkSoft, Theme.palette.orangeSoft, Theme.mintSoft]
        let actions = Theme.names.enumerated().map { index, name in
            ThemedSheetAction(title: (index == Theme.index ? "✓ " : "") + name, icon: "paintpalette", background: backgrounds[index]) { [weak self] in
                Theme.select(index)
                guard let self, let window = self.view.window else { return }
                UIView.transition(with: window, duration: 0.2, options: .transitionCrossDissolve) { window.rootViewController = MainViewController() }
            }
        }
        present(ThemedActionSheetController(title: "主题配色", actions: actions), animated: false)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool { textField.resignFirstResponder(); return true }
}

final class NavButton: UIButton {
    private let symbol = UIImageView()
    private let caption = UILabel()

    init(title: String, systemName: String) {
        super.init(frame: .zero)
        symbol.image = Theme.symbol(systemName, size: 19, weight: .medium)
        symbol.contentMode = .scaleAspectFit
        symbol.translatesAutoresizingMaskIntoConstraints = false
        caption.text = title
        caption.font = .systemFont(ofSize: 10, weight: .semibold)
        caption.textAlignment = .center
        caption.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbol)
        addSubview(caption)
        NSLayoutConstraint.activate([
            symbol.centerXAnchor.constraint(equalTo: centerXAnchor),
            symbol.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            symbol.widthAnchor.constraint(equalToConstant: 20),
            symbol.heightAnchor.constraint(equalToConstant: 20),
            caption.topAnchor.constraint(equalTo: symbol.bottomAnchor, constant: 3),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            caption.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2)
        ])
        setSelected(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    func setSelected(_ selected: Bool) {
        backgroundColor = selected ? Theme.pinkSoft : Theme.card
        symbol.tintColor = selected ? Theme.pink : Theme.secondaryInk
        caption.textColor = selected ? Theme.pink : Theme.secondaryInk
        layer.borderColor = Theme.line.cgColor
        layer.borderWidth = 0.5
    }

    func setRegularLayout(_ regular: Bool) {
        caption.font = .systemFont(ofSize: regular ? 11 : 10, weight: .semibold)
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: regular ? 21 : 19, weight: .medium)
    }
}

extension Notification.Name {
    static let addSnowAccount = Notification.Name("snowking.add-account")
    static let searchSnowAccounts = Notification.Name("snowking.search-accounts")
    static let closeSnowAccounts = Notification.Name("snowking.close-accounts")
    static let snowKingScriptsChanged = Notification.Name("snowking.scripts-changed")
}
