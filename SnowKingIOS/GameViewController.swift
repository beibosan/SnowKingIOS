import UIKit
import WebKit

import UniformTypeIdentifiers
final class GameViewController: UIViewController, WKNavigationDelegate {
    private var filePickerCoordinator: WebFilePickerCoordinator?
    private var account: SnowAccount
    private var webView: WKWebView!
    private var bridge: GameBridge!
    private var pendingAccount: SnowAccount?
    private var accountSwitchGeneration = 0
    private var contentController = WKUserContentController()
    private let accountButton = UIButton(type: .custom)
    private let progress = UIProgressView(progressViewStyle: .bar)
    private let toolbar = UIView()
    private let accountOverlay = UIView()
    private let accountPanel = UIStackView()

    init(account: SnowAccount) {
        self.account = account
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        NotificationCenter.default.addObserver(self, selector: #selector(cacheSettingChanged), name: .snowKingCacheSettingChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(gameCacheCleared), name: .snowKingGameCacheCleared, object: nil)
        view.backgroundColor = Theme.card
        buildWebView()
        buildToolbar()
        buildAccountOverlay()
        NotificationCenter.default.addObserver(self, selector: #selector(closeRequestedAccounts(_:)), name: .closeSnowAccounts, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scriptConfigurationChanged), name: .snowKingScriptsChanged, object: nil)
        loadGame()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard isViewLoaded, webView != nil else { return }
        webView.evaluateJavaScript("try { if (window.cc && cc.game && cc.game.resume) cc.game.resume(); } catch (_) {}")
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let pauseEnabled = UserDefaults.standard.object(forKey: "pause_background") == nil || UserDefaults.standard.bool(forKey: "pause_background")
        guard pauseEnabled else { return }
        webView?.evaluateJavaScript("try { if (window.cc && cc.game && cc.game.pause) cc.game.pause(); } catch (_) {}")
    }

    private func buildWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // The login bridge owns account state; persistent mode keeps large remote game bundles cached.
        let cacheEnabled = UserDefaults.standard.object(forKey: "cache_enabled") == nil || UserDefaults.standard.bool(forKey: "cache_enabled")
        config.websiteDataStore = cacheEnabled ? .default() : .nonPersistent()
        // The bundled Cocos page is loaded from file:// and then pulls remote bundles from HTTPS.
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        config.userContentController = contentController
        let content = contentController
        bridge = GameBridge(owner: self)
        content.add(bridge, name: "birdKingNative")
        content.add(bridge, name: "console")
        content.add(bridge, name: "heguangConsole")
        installUserScripts(for: account)
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.backgroundColor = .black
        webView.isOpaque = true
        webView.contentMode = .redraw
        webView.layer.contentsScale = UIScreen.main.scale
        webView.scrollView.layer.contentsScale = UIScreen.main.scale
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.translatesAutoresizingMaskIntoConstraints = false
        bridge.webView = webView
        bridge.requestImportFile = { [weak self] in self?.presentNativeImportPicker() }
        view.insertSubview(webView, at: 0)
    }

    private func installUserScripts(for account: SnowAccount) {
        let target = contentController
        target.removeAllUserScripts()
        target.addUserScript(bridge.userScript(for: account))
        BuiltinScriptStore.enabledSources.forEach { item in
            target.addUserScript(bridge.scriptUserScript(name: item.name, source: item.source))
        }
        BuiltinScriptStore.enabledManagedSources.forEach { item in
            target.addUserScript(bridge.scriptUserScript(name: item.name, source: item.source, waitForAccount: true))
        }
        LocalScriptStore.shared.enabledScripts.forEach { item in
            target.addUserScript(bridge.scriptUserScript(name: item.name, source: item.source, waitForAccount: true))
        }
    }

    private func buildToolbar() {
        toolbar.backgroundColor = Theme.gameBar
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        var accountConfig = UIButton.Configuration.plain()
        accountConfig.title = account.name
        accountConfig.image = Theme.symbol("chevron.down", size: 12, weight: .semibold)
        accountConfig.imagePlacement = .trailing
        accountConfig.imagePadding = 6
        accountConfig.baseForegroundColor = Theme.gameAccent
        accountConfig.background.backgroundColor = .clear
        accountConfig.background.strokeColor = .clear
        accountConfig.background.strokeWidth = 0
        accountButton.configuration = accountConfig
        accountButton.backgroundColor = .clear
        accountButton.contentHorizontalAlignment = .leading
        accountButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        accountButton.addTarget(self, action: #selector(toggleAccountOverlay), for: .touchUpInside)
        accountButton.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(accountButton)

        let refresh = roundToolbarButton(systemName: "arrow.clockwise", background: Theme.mintSoft)
        refresh.addTarget(self, action: #selector(reloadGame), for: .touchUpInside)
        toolbar.addSubview(refresh)
        let close = roundToolbarButton(systemName: "xmark", background: Theme.coralSoft)
        close.addTarget(self, action: #selector(closeGame), for: .touchUpInside)
        toolbar.addSubview(close)

        progress.progressTintColor = Theme.sky
        progress.trackTintColor = .clear
        progress.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(progress)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 48),
            accountButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 14),
            accountButton.topAnchor.constraint(equalTo: toolbar.topAnchor),
            accountButton.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor),
            refresh.leadingAnchor.constraint(equalTo: accountButton.trailingAnchor, constant: 4),
            refresh.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            refresh.widthAnchor.constraint(equalToConstant: 38),
            refresh.heightAnchor.constraint(equalToConstant: 38),
            close.leadingAnchor.constraint(equalTo: refresh.trailingAnchor),
            close.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -6),
            close.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 38),
            close.heightAnchor.constraint(equalToConstant: 38),
            accountButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),
            progress.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            progress.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            progress.heightAnchor.constraint(equalToConstant: 3)
        ])
        activateWebViewConstraints()
    }

    private func activateWebViewConstraints() {
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func roundToolbarButton(systemName: String, background: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(Theme.symbol(systemName, size: 16, weight: .semibold), for: .normal)
        button.tintColor = Theme.ink
        button.backgroundColor = background
        button.rounded(19, border: Theme.ink, width: 2)
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func buildAccountOverlay() {
        accountOverlay.backgroundColor = UIColor(red: 20 / 255, green: 24 / 255, blue: 22 / 255, alpha: 0.59)
        accountOverlay.isHidden = true
        accountOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(accountOverlay)
        let dismissTap = UITapGestureRecognizer(target: self, action: #selector(hideAccountOverlay))
        dismissTap.delegate = self
        accountOverlay.addGestureRecognizer(dismissTap)

        accountPanel.axis = .vertical
        accountPanel.spacing = 7
        accountPanel.backgroundColor = Theme.card
        accountPanel.layer.cornerRadius = 16
        accountPanel.layer.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        accountPanel.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 14, right: 14)
        accountPanel.isLayoutMarginsRelativeArrangement = true
        accountPanel.translatesAutoresizingMaskIntoConstraints = false
        accountOverlay.addSubview(accountPanel)
        NSLayoutConstraint.activate([
            accountOverlay.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            accountOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            accountOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            accountOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            accountPanel.topAnchor.constraint(equalTo: accountOverlay.topAnchor),
            accountPanel.leadingAnchor.constraint(equalTo: accountOverlay.leadingAnchor),
            accountPanel.trailingAnchor.constraint(equalTo: accountOverlay.trailingAnchor)
        ])
    }

    private func renderAccountPanel() {
        accountPanel.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let heading = UILabel()
        heading.text = "切换账号"
        heading.textColor = Theme.ink
        heading.font = .systemFont(ofSize: 16, weight: .bold)
        heading.heightAnchor.constraint(equalToConstant: 30).isActive = true
        accountPanel.addArrangedSubview(heading)

        AccountStore.shared.accounts.filter { !($0.binData ?? "").isEmpty }.forEach { candidate in
            var config = UIButton.Configuration.plain()
            config.title = candidate.name
            config.subtitle = candidate.group
            config.image = Theme.symbol(candidate.id == account.id ? "checkmark.circle.fill" : "person.crop.circle", size: 17, weight: .medium)
            config.imagePadding = 10
            config.baseForegroundColor = Theme.ink
            config.background.backgroundColor = candidate.id == account.id ? Theme.mintSoft : Theme.field
            config.background.cornerRadius = 10
            let row = UIButton(configuration: config)
            row.contentHorizontalAlignment = .leading
            row.heightAnchor.constraint(equalToConstant: 52).isActive = true
            row.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                self.hideAccountOverlay()
                if candidate.id != self.account.id { self.hotSwitch(to: candidate) }
            }, for: .touchUpInside)
            accountPanel.addArrangedSubview(row)
        }
    }

    @objc private func toggleAccountOverlay() { accountOverlay.isHidden ? showAccountOverlay() : hideAccountOverlay() }
    private func showAccountOverlay() { renderAccountPanel(); accountOverlay.isHidden = false }
    @objc private func hideAccountOverlay() { accountOverlay.isHidden = true }
    @objc private func reloadGame() {
        accountSwitchGeneration += 1
        pendingAccount = nil
        accountButton.isEnabled = true
        installUserScripts(for: account)
        webView.reload()
    }

    @objc private func scriptConfigurationChanged() {
        guard isViewLoaded, webView != nil else { return }
        accountSwitchGeneration += 1
        pendingAccount = nil
        accountButton.isEnabled = true
        installUserScripts(for: account)
        webView.reload()
    }
    @objc private func closeGame() {
        AccountStore.shared.updateStatus(ids: [account.id], status: "已关闭", operation: "关闭窗口")
        dismiss(animated: true)
    }

    @objc private func closeRequestedAccounts(_ notification: Notification) {
        guard let ids = notification.object as? Set<UUID>, ids.contains(account.id) else { return }
        closeGame()
    }

    private func hotSwitch(to target: SnowAccount) {
        let resolved = AccountStore.shared.accounts.first(where: { $0.id == target.id }) ?? target
        guard !(resolved.binData ?? "").isEmpty else {
            presentMessage(title: "无法切换账号", message: "该账号没有可用的 BIN/JSON 登录数据。")
            return
        }
        let previousID = account.id
        accountSwitchGeneration += 1
        let generation = accountSwitchGeneration
        pendingAccount = resolved
        accountButton.isEnabled = false
        account = resolved
        accountButton.configuration?.title = resolved.name
        AccountStore.shared.updateStatus(ids: [previousID], status: "已关闭", operation: "切换账号")
        AccountStore.shared.updateStatus(ids: [resolved.id], status: "运行中", operation: "切换账号")
        installUserScripts(for: resolved)
        let update = bridge.sessionUpdateScript(for: resolved)
        webView.evaluateJavaScript(update) { [weak self] _, error in
            guard let self, generation == self.accountSwitchGeneration else { return }
            if let error {
                self.recordGameReport(level: "error", event: "account_context_update_failed", detail: error.localizedDescription)
                self.rebuildForAccountSwitch(generation: generation)
                return
            }
            self.attemptHotSwitch(generation: generation, attempt: 0, prepareAccount: true)
        }
    }

    private func attemptHotSwitch(generation: Int, attempt: Int, prepareAccount: Bool) {
        guard generation == accountSwitchGeneration, webView != nil else { return }
        let function = prepareAccount ? "window.__yunqi_hotSwitchNativeAccount" : "window.__yunqi_retryHotSwitchNativeAccount"
        let script = """
        (function () {
          try {
            var fn = \(function);
            return typeof fn === 'function' ? fn() : 'missing';
          } catch (error) {
            console.error('[SnowKing Hot Switch]', error);
            return 'account_error';
          }
        })();
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self, generation == self.accountSwitchGeneration else { return }
            let state = (result as? String) ?? ""
            if state == "switched" || (result as? Bool) == true {
                self.pendingAccount = nil
                self.accountButton.isEnabled = true
                self.recordGameReport(level: "info", event: "account_hot_switch_succeeded", detail: self.account.name)
                return
            }
            if attempt + 1 < 20 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                    self?.attemptHotSwitch(generation: generation, attempt: attempt + 1, prepareAccount: false)
                }
                return
            }
            self.rebuildForAccountSwitch(generation: generation)
        }
    }

    private func rebuildForAccountSwitch(generation: Int) {
        guard generation == accountSwitchGeneration else { return }
        webView.stopLoading()
        rebuildWebView()
        recordGameReport(level: "info", event: "account_switch_rebuild_fallback", detail: account.name)
        loadGame()
    }

    private func rebuildWebView() {
        let oldWebView = webView
        let oldContent = oldWebView?.configuration.userContentController
        ["birdKingNative", "console", "heguangConsole"].forEach { oldContent?.removeScriptMessageHandler(forName: $0) }
        oldWebView?.navigationDelegate = nil
        oldWebView?.stopLoading()
        oldWebView?.removeFromSuperview()
        contentController = WKUserContentController()
        buildWebView()
        activateWebViewConstraints()
        view.bringSubviewToFront(toolbar)
        view.bringSubviewToFront(progress)
        view.bringSubviewToFront(accountOverlay)
    }

    private func loadGame() {
        guard let root = GameAssetStore.shared.url(forResource: "index", withExtension: "html") else {
            presentMessage(title: "资源错误", message: "未找到 GameAssets/index.html")
            return
        }
        webView.loadFileURL(root, allowingReadAccessTo: root.deletingLastPathComponent())
    }

    private func presentNativeImportPicker() {
        filePickerCoordinator = WebFilePickerCoordinator(presenter: self) { [weak self] urls in
            self?.filePickerCoordinator = nil
            self?.bridge.completeImportFile(urls?.first)
        }
        filePickerCoordinator?.present()
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { progress.isHidden = false; progress.setProgress(0.2, animated: false) }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { progress.setProgress(0.7, animated: true) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        progress.setProgress(1, animated: true)
        pendingAccount = nil
        accountButton.isEnabled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.progress.isHidden = true }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { handleLoadFailure(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { handleLoadFailure(error) }

    private func handleLoadFailure(_ error: Error) {
        progress.isHidden = true
        pendingAccount = nil
        accountButton.isEnabled = true
        recordGameReport(level: "error", event: "webview_load_failed", detail: error.localizedDescription)
        presentMessage(title: "游戏加载失败", message: error.localizedDescription)
    }

    private func presentMessage(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    func recordGameReport(level: String, event: String, detail: String) { NSLog("[SnowKing] %@ %@ %@", level, event, detail) }

    func cacheDecodedLoginInfo(_ value: String, binHash: String) {
        guard !value.isEmpty, !binHash.isEmpty else { return }
        var accounts = AccountStore.shared.accounts
        let candidates = [pendingAccount, account].compactMap { $0 }
        guard let target = candidates.first(where: { bridge.contentHash(for: $0) == binHash }),
              let index = accounts.firstIndex(where: { $0.id == target.id }) else { return }
        accounts[index].decodedLoginInfo = value
        accounts[index].decodedBinHash = binHash
        if account.id == target.id {
            account.decodedLoginInfo = value
            account.decodedBinHash = binHash
        }
        if pendingAccount?.id == target.id {
            pendingAccount?.decodedLoginInfo = value
            pendingAccount?.decodedBinHash = binHash
        }
        AccountStore.shared.replace(accounts)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        let content = webView?.configuration.userContentController
        content?.removeScriptMessageHandler(forName: "birdKingNative")
        content?.removeScriptMessageHandler(forName: "console")
        content?.removeScriptMessageHandler(forName: "heguangConsole")
    }

    @objc private func cacheSettingChanged() {
        guard isViewLoaded, webView != nil else { return }
        accountSwitchGeneration += 1
        pendingAccount = nil
        accountButton.isEnabled = true
        rebuildWebView()
        loadGame()
    }

    @objc private func gameCacheCleared() {
        guard isViewLoaded, webView != nil else { return }
        reloadGame()
    }
}

extension GameViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let touchedView = touch.view else { return true }
        return !touchedView.isDescendant(of: accountPanel)
    }
}

final class WebFilePickerCoordinator: NSObject, UIDocumentPickerDelegate {
    private weak var presenter: UIViewController?
    private let completion: ([URL]?) -> Void
    private var finished = false

    init(presenter: UIViewController, completion: @escaping ([URL]?) -> Void) {
        self.presenter = presenter
        self.completion = completion
        super.init()
    }

    func present() {
        let types: [UTType] = [.json, .data, .plainText, .item]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        presenter?.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finish(urls)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(nil)
    }

    private func finish(_ urls: [URL]?) {
        guard !finished else { return }
        finished = true
        completion(urls)
    }
}
