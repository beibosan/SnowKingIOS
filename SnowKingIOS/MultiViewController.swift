import UIKit
import WebKit
import UniformTypeIdentifiers

final class MultiViewController: UIViewController {
    private var filePickerCoordinators: [ObjectIdentifier: WebFilePickerCoordinator] = [:]
    var onClose: (() -> Void)?
    private var vertical: Bool
    private var accounts: [SnowAccount]
    private var verticalSlots: [SnowAccount?]
    private let titleLabel = UILabel()
    private let stage = UIStackView()
    private let scroll = UIScrollView()
    private var verticalMode = 1
    private var activeSlot = 0
    private var syncEnabled = false
    private var webViews: [UUID: WKWebView] = [:]
    private var bridges: [UUID: GameBridge] = [:]
    private var syncBridges: [UUID: MultiSyncBridge] = [:]
    private var syncDisabledIDs = Set<UUID>()
    private var lastRenderedSize = CGSize.zero
    private var nextWebLoadOrder = 0

    init(vertical: Bool, accounts: [SnowAccount]) {
        self.vertical = vertical
        self.accounts = accounts
        self.verticalSlots = (0..<4).map { $0 < accounts.count ? accounts[$0] : nil }
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.cream
        build()
        NotificationCenter.default.addObserver(self, selector: #selector(closeRequestedAccounts(_:)), name: .closeSnowAccounts, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(scriptConfigurationChanged), name: .snowKingScriptsChanged, object: nil)
        let runningIDs = Set((vertical ? verticalSlots.compactMap { $0 } : accounts).map(\.id))
        AccountStore.shared.updateStatus(ids: runningIDs, status: "运行中", operation: "启动多开")
        NotificationCenter.default.addObserver(self, selector: #selector(cacheSettingChanged), name: .snowKingCacheSettingChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(gameCacheCleared), name: .snowKingGameCacheCleared, object: nil)
        renderStage()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = view.bounds.size
        guard size.width > 0, size.height > 0,
              abs(size.width - lastRenderedSize.width) > 1 || abs(size.height - lastRenderedSize.height) > 1 else { return }
        lastRenderedSize = size
        renderStage()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        webViews.values.forEach { $0.evaluateJavaScript("try { if (window.cc && cc.game && cc.game.resume) cc.game.resume(); } catch (_) {}") }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let pauseEnabled = UserDefaults.standard.object(forKey: "pause_background") == nil || UserDefaults.standard.bool(forKey: "pause_background")
        guard pauseEnabled else { return }
        webViews.values.forEach { $0.evaluateJavaScript("try { if (window.cc && cc.game && cc.game.pause) cc.game.pause(); } catch (_) {}") }
    }

    private func build() {
        let top = UIView()
        top.backgroundColor = Theme.pinkSoft
        top.rounded(12)
        top.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(top)
        let icon = UIImageView(image: Theme.lineIcon("batch", size: 16))
        icon.tintColor = Theme.secondaryInk
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        top.addSubview(icon)
        titleLabel.textColor = Theme.ink
        titleLabel.font = .systemFont(ofSize: 13, weight: .bold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        top.addSubview(titleLabel)
        let layout = controlButton(iconName: "layout", background: Theme.mintSoft)
        layout.addTarget(self, action: #selector(changeLayout), for: .touchUpInside)
        top.addSubview(layout)
        let sync = controlButton(iconName: "lock-open", background: Theme.mintSoft)
        sync.tag = 100
        sync.addTarget(self, action: #selector(toggleSync(_:)), for: .touchUpInside)
        top.addSubview(sync)
        let clear = controlButton(iconName: "close", background: Theme.coralSoft)
        clear.addTarget(self, action: #selector(clearSlots), for: .touchUpInside)
        top.addSubview(clear)

        scroll.alwaysBounceVertical = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stage.axis = .vertical
        stage.spacing = 4
        stage.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stage)
        NSLayoutConstraint.activate([
            top.topAnchor.constraint(equalTo: view.topAnchor, constant: 3),
            top.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            top.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            top.heightAnchor.constraint(equalToConstant: 40),
            icon.leadingAnchor.constraint(equalTo: top.leadingAnchor, constant: 7),
            icon.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            layout.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 4),
            layout.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            layout.widthAnchor.constraint(equalToConstant: 30),
            layout.heightAnchor.constraint(equalToConstant: 30),
            sync.leadingAnchor.constraint(equalTo: layout.trailingAnchor, constant: 3),
            sync.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            sync.widthAnchor.constraint(equalToConstant: 30),
            sync.heightAnchor.constraint(equalToConstant: 30),
            clear.leadingAnchor.constraint(equalTo: sync.trailingAnchor, constant: 3),
            clear.trailingAnchor.constraint(equalTo: top.trailingAnchor, constant: -3),
            clear.centerYAnchor.constraint(equalTo: top.centerYAnchor),
            clear.widthAnchor.constraint(equalToConstant: 30),
            clear.heightAnchor.constraint(equalToConstant: 30),
            scroll.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 3),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -4),
            stage.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stage.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor),
            stage.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stage.heightAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.heightAnchor)
        ])
    }

    private func controlButton(iconName: String, background: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(Theme.lineIcon(iconName, size: 16), for: .normal)
        button.tintColor = Theme.ink
        button.backgroundColor = background
        button.rounded(15)
        button.imageView?.contentMode = .scaleAspectFit
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    @objc private func changeLayout() {
        if vertical {
            verticalMode = verticalMode >= 3 ? 1 : verticalMode + 1
        } else {
            vertical = true
            verticalSlots = (0..<4).map { $0 < accounts.count ? accounts[$0] : nil }
        }
        renderStage()
    }

    @objc private func toggleSync(_ sender: UIButton) {
        syncEnabled.toggle()
        sender.setImage(Theme.lineIcon(syncEnabled ? "lock" : "lock-open", size: 16), for: .normal)
        sender.backgroundColor = syncEnabled ? Theme.mint : Theme.mintSoft
        let value = syncEnabled ? "true" : "false"
        webViews.values.forEach { $0.evaluateJavaScript("window.__snowkingSyncEnabled = \(value);") }
        updateTitle()
    }

    @objc private func clearSlots() {
        onClose?()
    }

    private func renderStage() {
        applyOrientationModeToWebViews()
        stage.arrangedSubviews.forEach { $0.removeFromSuperview() }
        updateTitle()
        if vertical { renderVertical(accounts) } else { renderHorizontal(accounts) }
        DispatchQueue.main.async { [weak self] in
            self?.applyOrientationModeToWebViews()
        }
    }

    private func updateTitle() {
        let verticalCount = verticalSlots.compactMap { $0 }.count
        let syncState = syncEnabled ? " · 同步开" : ""
        titleLabel.text = vertical ? "纵向多开 · \(verticalCount) 个账号 · 模式 \(verticalMode)\(syncState)" : "横向多开 · \(accounts.count) 个窗口\(syncState)"
    }

    private func renderHorizontal(_ accounts: [SnowAccount]) {
        guard !accounts.isEmpty else { return }
        var accountIndex = 0
        let rows = horizontalRows(accounts.count)
        let stageWidth = max(320, view.bounds.width - 8)
        let usableHeight = max(250, availableStageHeight - stage.spacing * CGFloat(max(0, rows.count - 1)))
        rows.forEach { slots in
            let row = UIStackView()
            row.axis = .horizontal
            row.alignment = .fill
            row.distribution = .fillEqually
            row.spacing = 3
            let minimumHeight: CGFloat = slots == 1 ? 250 : 142
            let cardWidth = (stageWidth - row.spacing * CGFloat(max(0, slots - 1))) / CGFloat(slots)
            let preferredAspect: CGFloat = slots == 1 ? 1.68 : 1.55
            let preferredHeight = max(minimumHeight, cardWidth / preferredAspect)
            let fitHeight = max(minimumHeight, usableHeight / CGFloat(rows.count))
            let rowHeight = min(preferredHeight, fitHeight)
            let targetAspect: CGFloat = slots == 1 ? 1.72 : 1.55
            let targetWidth = min(stageWidth, rowHeight * targetAspect * CGFloat(slots) + row.spacing * CGFloat(max(0, slots - 1)))
            let horizontalInset = max(0, (stageWidth - targetWidth) / 2)
            row.isLayoutMarginsRelativeArrangement = true
            row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 0, leading: horizontalInset, bottom: 0, trailing: horizontalInset)
            for _ in 0..<slots where accountIndex < accounts.count {
                row.addArrangedSubview(windowCard(accounts[accountIndex], compact: slots > 1))
                accountIndex += 1
            }
            row.heightAnchor.constraint(equalToConstant: rowHeight).isActive = true
            stage.addArrangedSubview(row)
        }
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        stage.addArrangedSubview(spacer)
    }

    private func horizontalRows(_ count: Int) -> [Int] {
        switch count {
        case 1: return [1]
        case 2: return [1, 1]
        case 3: return [1, 1, 1]
        case 4: return [2, 2]
        case 5: return [2, 1, 2]
        case 6: return [2, 1, 2, 1]
        default:
            return stride(from: 0, to: count, by: 2).map { min(2, count - $0) }
        }
    }

    private var availableStageHeight: CGFloat {
        max(220, view.bounds.height - 50)
    }

    private func renderVertical(_ accounts: [SnowAccount]) {
        let slots = verticalSlots
        if verticalMode == 1 {
            let tabs = UIStackView()
            tabs.axis = .horizontal
            tabs.distribution = .fillEqually
            tabs.spacing = 3
            slots.enumerated().forEach { index, account in
                let tab = UIButton(type: .system)
                tab.setTitle(account?.name ?? "槽位 \(index + 1)", for: .normal)
                tab.setTitleColor(index == activeSlot ? Theme.ink : Theme.secondaryInk, for: .normal)
                tab.backgroundColor = index == activeSlot ? Theme.mintSoft : Theme.controlSoft
                tab.titleLabel?.font = .systemFont(ofSize: 10, weight: .semibold)
                tab.rounded(8)
                tab.tag = index
                tab.addTarget(self, action: #selector(changeActiveSlot(_:)), for: .touchUpInside)
                tabs.addArrangedSubview(tab)
            }
            tabs.heightAnchor.constraint(equalToConstant: 36).isActive = true
            stage.addArrangedSubview(tabs)
            let active = windowCard(slots[activeSlot], compact: false, slot: activeSlot)
            active.heightAnchor.constraint(equalToConstant: max(220, availableStageHeight - 39)).isActive = true
            stage.addArrangedSubview(active)
        } else if verticalMode == 2 {
            for rowIndex in 0..<2 {
                let row = UIStackView()
                row.axis = .horizontal
                row.spacing = 3
                row.distribution = .fillEqually
                row.addArrangedSubview(windowCard(slots[rowIndex * 2], compact: true, slot: rowIndex * 2))
                row.addArrangedSubview(windowCard(slots[rowIndex * 2 + 1], compact: true, slot: rowIndex * 2 + 1))
                row.heightAnchor.constraint(equalToConstant: max(190, (availableStageHeight - stage.spacing) / 2)).isActive = true
                stage.addArrangedSubview(row)
            }
        } else {
            let top = UIStackView()
            top.axis = .horizontal
            top.spacing = 3
            top.distribution = .fillEqually
            for index in slots.indices where index != activeSlot {
                let card = windowCard(slots[index], compact: true, slot: index)
                let tap = UITapGestureRecognizer(target: self, action: #selector(focusSlot(_:)))
                tap.name = String(index)
                card.addGestureRecognizer(tap)
                card.isUserInteractionEnabled = true
                top.addArrangedSubview(card)
            }
            let previewHeight = max(120, availableStageHeight * (view.bounds.width < 600 ? 0.24 : 0.28))
            top.heightAnchor.constraint(equalToConstant: previewHeight).isActive = true
            stage.addArrangedSubview(top)
            let focus = windowCard(slots[activeSlot], compact: false, slot: activeSlot)
            focus.heightAnchor.constraint(equalToConstant: max(220, availableStageHeight - previewHeight - stage.spacing)).isActive = true
            stage.addArrangedSubview(focus)
        }
    }

    private func windowCard(_ account: SnowAccount?, compact: Bool, slot: Int? = nil) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.backgroundColor = .black
        container.rounded(6, border: Theme.line)
        let bar = UIView()
        bar.backgroundColor = Theme.gameBar
        bar.heightAnchor.constraint(equalToConstant: 18).isActive = true
        let dot = UIView()
        dot.backgroundColor = account == nil ? Theme.statusIdle : Theme.statusRunning
        dot.rounded(2.5)
        dot.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(dot)
        let label = UILabel()
        label.text = account?.name ?? "待启动"
        label.textColor = Theme.ink
        label.font = .systemFont(ofSize: compact ? 8 : 10, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(label)
        let lock = UIButton(type: .system)
        let syncAllowed = account.map { !syncDisabledIDs.contains($0.id) } ?? false
        lock.setImage(Theme.lineIcon(syncAllowed ? "lock" : "lock-open", size: 8), for: .normal)
        lock.tintColor = Theme.secondaryInk
        lock.imageView?.contentMode = .scaleAspectFit
        lock.accessibilityLabel = syncAllowed ? "参与触摸同步" : "不参与触摸同步"
        lock.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(lock)
        let close = UIButton(type: .system)
        close.setImage(Theme.lineIcon("close", size: 8), for: .normal)
        close.tintColor = Theme.coral
        close.imageView?.contentMode = .scaleAspectFit
        close.accessibilityLabel = "关闭窗口"
        close.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(close)
        if let account {
            lock.addAction(UIAction { [weak self, weak lock] _ in
                guard let self else { return }
                if self.syncDisabledIDs.contains(account.id) { self.syncDisabledIDs.remove(account.id) }
                else { self.syncDisabledIDs.insert(account.id) }
                let enabled = !self.syncDisabledIDs.contains(account.id)
                lock?.setImage(Theme.lineIcon(enabled ? "lock" : "lock-open", size: 8), for: .normal)
                lock?.accessibilityLabel = enabled ? "参与触摸同步" : "不参与触摸同步"
            }, for: .touchUpInside)
            close.addAction(UIAction { [weak self] _ in self?.closeWindow(account, slot: slot) }, for: .touchUpInside)
        } else {
            lock.isEnabled = false
            close.isHidden = true
        }
        NSLayoutConstraint.activate([
            dot.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 4),
            dot.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 5),
            dot.heightAnchor.constraint(equalToConstant: 5),
            label.leadingAnchor.constraint(equalTo: dot.trailingAnchor, constant: 3),
            label.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            close.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -1),
            close.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 16),
            close.heightAnchor.constraint(equalToConstant: 16),
            lock.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -2),
            lock.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            lock.widthAnchor.constraint(equalToConstant: 16),
            lock.heightAnchor.constraint(equalToConstant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: lock.leadingAnchor, constant: -3)
        ])
        container.addArrangedSubview(bar)
        let viewport: UIView
        if let account {
            let game = gameWebView(for: account)
            if vertical {
                game.transform = .identity
                viewport = game
            } else {
                viewport = LandscapeGameViewport(webView: game)
            }
        } else {
            let empty = UIView()
            empty.backgroundColor = .black
            let hint = UILabel()
            hint.text = "+\n选择账号"
            hint.numberOfLines = 2
            hint.textAlignment = .center
            hint.textColor = .white.withAlphaComponent(0.72)
            hint.font = .systemFont(ofSize: compact ? 10 : 13, weight: .semibold)
            hint.translatesAutoresizingMaskIntoConstraints = false
            empty.addSubview(hint)
            NSLayoutConstraint.activate([hint.centerXAnchor.constraint(equalTo: empty.centerXAnchor), hint.centerYAnchor.constraint(equalTo: empty.centerYAnchor)])
            viewport = empty
        }
        container.addArrangedSubview(viewport)
        if account == nil, let slot {
            let tap = UITapGestureRecognizer(target: self, action: #selector(selectSlot(_:)))
            tap.name = String(slot)
            container.addGestureRecognizer(tap)
            container.isUserInteractionEnabled = true
        }
        return container
    }

    private func gameWebView(for account: SnowAccount) -> WKWebView {
        if let existing = webViews[account.id] { return existing }
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        // Share the heavy resource cache; account-sensitive storage keys are namespaced in index.html.
        let cacheEnabled = UserDefaults.standard.object(forKey: "cache_enabled") == nil || UserDefaults.standard.bool(forKey: "cache_enabled")
        configuration.websiteDataStore = cacheEnabled ? .default() : .nonPersistent()
        // The bundled page is file://, while game bundles are downloaded from HTTPS.
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        configuration.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        let bridge = GameBridge()
        let syncBridge = MultiSyncBridge(owner: self, accountID: account.id)
        let content = configuration.userContentController
        content.add(bridge, name: "birdKingNative")
        content.add(bridge, name: "console")
        content.add(bridge, name: "heguangConsole")
        content.add(syncBridge, name: "snowKingSync")
        content.addUserScript(bridge.userScript(
            for: account,
            isolateAccountStorage: true,
            enableIPadLandscapeRotation: !vertical
        ))
        content.addUserScript(WKUserScript(source: multiPerformanceScript(), injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        content.addUserScript(WKUserScript(source: Self.syncCaptureScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        BuiltinScriptStore.enabledSources.forEach { script in
            content.addUserScript(bridge.scriptUserScript(name: script.name, source: script.source))
        }
        BuiltinScriptStore.enabledManagedSources.forEach { script in
            content.addUserScript(bridge.scriptUserScript(name: script.name, source: script.source, waitForAccount: true))
        }
        LocalScriptStore.shared.enabledScripts.forEach { script in
            content.addUserScript(bridge.scriptUserScript(name: script.name, source: script.source, waitForAccount: true))
        }
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        bridge.webView = webView
        bridge.requestImportFile = { [weak self, weak bridge, weak webView] in
            guard let self, let webView, let bridge else { return }
            self.presentNativeImportPicker(for: webView, bridge: bridge)
        }
        bridges[account.id] = bridge
        syncBridges[account.id] = syncBridge
        webViews[account.id] = webView
        let loadOrder = nextWebLoadOrder
        nextWebLoadOrder += 1
        if let root = GameAssetStore.shared.url(forResource: "index", withExtension: "html") {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(loadOrder) * 1.2) { [weak self, weak webView] in
                guard let self, let webView, self.webViews[account.id] === webView else { return }
                webView.loadFileURL(root, allowingReadAccessTo: root.deletingLastPathComponent())
            }
        }
        return webView
    }

    fileprivate func relaySyncEvent(from sourceID: UUID, body: [String: Any]) {
        guard syncEnabled, !syncDisabledIDs.contains(sourceID),
              let data = try? JSONSerialization.data(withJSONObject: body),
              let json = String(data: data, encoding: .utf8) else { return }
        for (id, webView) in webViews where id != sourceID && !syncDisabledIDs.contains(id) {
            webView.evaluateJavaScript("window.__snowkingReceiveSync && window.__snowkingReceiveSync(\(json));")
        }
    }

    private func closeWindow(_ account: SnowAccount, slot: Int?) {
        if vertical, let slot, verticalSlots.indices.contains(slot) {
            verticalSlots[slot] = nil
            if activeSlot == slot, let next = verticalSlots.firstIndex(where: { $0 != nil }) { activeSlot = next }
        } else {
            accounts.removeAll { $0.id == account.id }
        }
        releaseWebView(for: account.id)
        AccountStore.shared.updateStatus(ids: [account.id], status: "已关闭", operation: "关闭多开窗口")
        renderStage()
    }

    @objc private func closeRequestedAccounts(_ notification: Notification) {
        guard let ids = notification.object as? Set<UUID>, !ids.isEmpty else { return }
        if vertical {
            for index in verticalSlots.indices where verticalSlots[index].map({ ids.contains($0.id) }) == true {
                if let id = verticalSlots[index]?.id { releaseWebView(for: id) }
                verticalSlots[index] = nil
            }
            if verticalSlots[activeSlot] == nil,
               let next = verticalSlots.firstIndex(where: { $0 != nil }) { activeSlot = next }
        } else {
            accounts.filter { ids.contains($0.id) }.forEach { releaseWebView(for: $0.id) }
            accounts.removeAll { ids.contains($0.id) }
        }
        AccountStore.shared.updateStatus(ids: ids, status: "已关闭", operation: "批量关闭")
        renderStage()
    }

    private func releaseWebView(for id: UUID) {
        guard let webView = webViews.removeValue(forKey: id) else { return }
        let content = webView.configuration.userContentController
        ["birdKingNative", "console", "heguangConsole", "snowKingSync"].forEach { content.removeScriptMessageHandler(forName: $0) }
        webView.stopLoading()
        webView.removeFromSuperview()
        bridges.removeValue(forKey: id)
        syncBridges.removeValue(forKey: id)
        syncDisabledIDs.remove(id)
    }

    @objc private func scriptConfigurationChanged() {
        Array(webViews.keys).forEach { releaseWebView(for: $0) }
        nextWebLoadOrder = 0
        renderStage()
    }

    private static let syncCaptureScript = """
    (function () {
      if (window.__snowkingSyncInstalled) return;
      window.__snowkingSyncInstalled = true;
      window.__snowkingSyncEnabled = false;
      var dispatching = false;
      function send(type, touchList) {
        if (!window.__snowkingSyncEnabled || dispatching || !touchList || !touchList.length || !window.webkit || !window.webkit.messageHandlers.snowKingSync) return;
        var touches = Array.prototype.map.call(touchList, function (touch) {
          return {
            id: touch.identifier || 0,
            x: Math.max(0, Math.min(1, touch.clientX / Math.max(1, window.innerWidth))),
            y: Math.max(0, Math.min(1, touch.clientY / Math.max(1, window.innerHeight)))
          };
        });
        window.webkit.messageHandlers.snowKingSync.postMessage({
          type: type,
          touches: touches
        });
      }
      ['touchstart', 'touchmove', 'touchend', 'touchcancel'].forEach(function (type) {
        document.addEventListener(type, function (event) {
          send(type, event.changedTouches);
        }, { capture: true, passive: true });
      });
      window.__snowkingReceiveSync = function (payload) {
        dispatching = true;
        try {
          var points = payload.touches || [];
          if (!points.length) { dispatching = false; return; }
          var x = points[0].x * window.innerWidth;
          var y = points[0].y * window.innerHeight;
          var target = document.elementFromPoint(x, y) || document.querySelector('canvas') || document.body;
          var delivered = false;
          if (typeof Touch === 'function' && typeof TouchEvent === 'function') {
            try {
              var changed = points.map(function (point) {
                var px = point.x * window.innerWidth, py = point.y * window.innerHeight;
                return new Touch({ identifier: point.id + 9876, target: target, clientX: px, clientY: py, pageX: px, pageY: py, screenX: px, screenY: py });
              });
              var active = payload.type === 'touchend' || payload.type === 'touchcancel' ? [] : changed;
              target.dispatchEvent(new TouchEvent(payload.type, { touches: active, targetTouches: active, changedTouches: changed, bubbles: true, cancelable: true }));
              delivered = true;
            } catch (_) {}
          }
          if (!delivered) {
            points.forEach(function (point) {
              var px = point.x * window.innerWidth, py = point.y * window.innerHeight;
              if (typeof PointerEvent === 'function') {
                var pointerType = payload.type === 'touchstart' ? 'pointerdown' : payload.type === 'touchmove' ? 'pointermove' : 'pointerup';
                target.dispatchEvent(new PointerEvent(pointerType, { pointerId: point.id + 9876, pointerType: 'touch', clientX: px, clientY: py, bubbles: true, cancelable: true }));
              } else if (typeof MouseEvent === 'function') {
                var mouseType = payload.type === 'touchstart' ? 'mousedown' : payload.type === 'touchmove' ? 'mousemove' : 'mouseup';
                target.dispatchEvent(new MouseEvent(mouseType, { clientX: px, clientY: py, bubbles: true, cancelable: true }));
              }
            });
          }
        } catch (_) {}
        dispatching = false;
      };
    })();
    """

    private func multiPerformanceScript() -> String {
        let mobileMode = vertical ? "false" : "true"
        return """
    (function () {
      window.__SNOWKING_FORCE_UPRIGHT_GAME__ = \(vertical ? "true" : "false");
      var attempts = 0;
      var timer = setInterval(function () {
        attempts += 1;
        try {
          if (window.cc && cc.view) {
            if (cc.sys) cc.sys.isMobile = \(mobileMode);
            cc.view.enableRetina(false);
            if (cc.macro && cc.view.setOrientation) cc.view.setOrientation(cc.macro.ORIENTATION_PORTRAIT);
            cc.view.resizeWithBrowserSize(true);
            if (typeof cc.view._resizeEvent === 'function') cc.view._resizeEvent(false);
            if (cc.game && typeof cc.game.setFrameRate === 'function') cc.game.setFrameRate(30);
            clearInterval(timer);
          }
        } catch (_) {}
        if (attempts >= 120) clearInterval(timer);
      }, 250);
    })();
    """
    }

    private func applyOrientationModeToWebViews() {
        let mobileMode = vertical ? "false" : "true"
        let forceUpright = vertical ? "true" : "false"
        let source = """
        (function () {
          window.__SNOWKING_FORCE_UPRIGHT_GAME__ = \(forceUpright);
          try {
            if (window.cc && cc.sys) cc.sys.isMobile = \(mobileMode);
            if (window.cc && cc.view) {
              if (cc.macro && cc.view.setOrientation) cc.view.setOrientation(cc.macro.ORIENTATION_PORTRAIT);
              cc.view.resizeWithBrowserSize(true);
              if (typeof cc.view._resizeEvent === 'function') cc.view._resizeEvent(false);
            }
            window.dispatchEvent(new Event('resize'));
          } catch (_) {}
        })();
        """
        webViews.values.forEach { $0.evaluateJavaScript(source) }
    }

    @objc private func selectSlot(_ gesture: UITapGestureRecognizer) {
        guard let value = gesture.name, let slot = Int(value) else { return }
        let picker = SlotAccountPickerViewController(accounts: AccountStore.shared.accounts, selected: verticalSlots.compactMap { $0 })
        picker.onSelect = { [weak self] account in
            guard let self else { return }
            self.dismiss(animated: true) {
                for index in self.verticalSlots.indices where self.verticalSlots[index]?.id == account.id { self.verticalSlots[index] = nil }
                self.verticalSlots[slot] = account
                self.activeSlot = slot
                self.renderStage()
            }
        }
        present(UINavigationController(rootViewController: picker), animated: true)
    }

    @objc private func changeActiveSlot(_ sender: UIButton) { activeSlot = sender.tag; renderStage() }
    @objc private func focusSlot(_ gesture: UITapGestureRecognizer) {
        guard let value = gesture.name, let slot = Int(value) else { return }
        activeSlot = slot
        renderStage()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        let activeIDs = Set(webViews.keys)
        Array(activeIDs).forEach { releaseWebView(for: $0) }
        if !activeIDs.isEmpty {
            AccountStore.shared.updateStatus(ids: activeIDs, status: "已关闭", operation: "退出多开")
        }
    }

    private func presentNativeImportPicker(for webView: WKWebView, bridge: GameBridge) {
        let key = ObjectIdentifier(webView)
        let coordinator = WebFilePickerCoordinator(presenter: self) { [weak self, weak webView] urls in
            if let webView { self?.filePickerCoordinators.removeValue(forKey: ObjectIdentifier(webView)) }
            bridge.completeImportFile(urls?.first)
        }
        filePickerCoordinators[key] = coordinator
        coordinator.present()
    }

    @objc private func cacheSettingChanged() {
        resizeWorkItem?.cancel()
        Array(webViews.keys).forEach { releaseWebView(for: $0) }
        nextWebLoadOrder = 0
        renderStage()
    }

    @objc private func gameCacheCleared() {
        guard let root = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "GameAssets") else { return }
        for (index, webView) in webViews.values.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.8) { [weak self, weak webView] in
                guard let self, let webView, self.webViews.values.contains(where: { $0 === webView }) else { return }
                webView.loadFileURL(root, allowingReadAccessTo: root.deletingLastPathComponent())
            }
        }
    }
}

private final class LandscapeGameViewport: UIView {
    private let webView: WKWebView
    private var lastWebSize = CGSize.zero

    init(webView: WKWebView) {
        self.webView = webView
        super.init(frame: .zero)
        backgroundColor = .black
        clipsToBounds = true
        addSubview(webView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let size = CGSize(
            width: bounds.width,
            height: min(bounds.height, (bounds.width * 9.0 / 16.0).rounded())
        )
        webView.transform = .identity
        webView.frame = CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        ).integral
        guard abs(size.width - lastWebSize.width) > 1 || abs(size.height - lastWebSize.height) > 1 else { return }
        lastWebSize = size
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak webView] in
            webView?.evaluateJavaScript("try { window.dispatchEvent(new Event('resize')); if (window.cc && cc.view) cc.view.resizeWithBrowserSize(true); } catch (_) {}")
        }
    }
}

final class MultiSyncBridge: NSObject, WKScriptMessageHandler {
    private weak var owner: MultiViewController?
    private let accountID: UUID

    init(owner: MultiViewController, accountID: UUID) {
        self.owner = owner
        self.accountID = accountID
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "snowKingSync", let body = message.body as? [String: Any] else { return }
        owner?.relaySyncEvent(from: accountID, body: body)
    }
}

final class MultiAccountPickerViewController: UITableViewController {
    var onStart: (([SnowAccount]) -> Void)?
    private let accounts: [SnowAccount]
    private let vertical: Bool
    private var selectedIDs: Set<UUID>
    private var activeGroup = "全部"

    private var filteredAccounts: [SnowAccount] {
        accounts.filter { account in
            if activeGroup == "全部" { return true }
            if activeGroup == "未分组" { return account.group.isEmpty || account.group == "未分组" }
            return account.group == activeGroup
        }
    }

    init(accounts: [SnowAccount], vertical: Bool) {
        self.accounts = accounts
        self.vertical = vertical
        self.selectedIDs = Set(accounts.prefix(2).map(\.id))
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "选择多开账号"
        view.backgroundColor = Theme.page
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "进入多开", style: .done, target: self, action: #selector(start))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Account")
    }

    @objc private func cancel() { dismiss(animated: true) }
    @objc private func start() {
        let selected = accounts.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { return }
        onStart?(selected)
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 1 : filteredAccounts.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section == 1 else { return nil }
        return vertical ? "纵向最多选择 4 个账号" : "选择需要同时运行的账号"
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Account", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            content.text = "账号分组 · \(activeGroup)"
            content.secondaryText = "\(filteredAccounts.count) 个账号"
            content.image = Theme.symbol("folder", size: 17, weight: .medium)
            cell.contentConfiguration = content
            cell.accessoryType = .disclosureIndicator
            return cell
        }
        let account = filteredAccounts[indexPath.row]
        content.text = account.name
        content.secondaryText = account.group
        content.image = Theme.symbol("person.crop.circle", size: 17, weight: .medium)
        cell.contentConfiguration = content
        cell.accessoryType = selectedIDs.contains(account.id) ? .checkmark : .none
        cell.tintColor = Theme.mint
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            showGroupPicker(source: tableView.cellForRow(at: indexPath))
            return
        }
        let id = filteredAccounts[indexPath.row].id
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else if !vertical || selectedIDs.count < 4 { selectedIDs.insert(id) }
        tableView.reloadRows(at: [indexPath], with: .automatic)
    }

    private func showGroupPicker(source: UIView?) {
        let groups = ["全部", "未分组"] + GroupStore.shared.groups
        let actions = groups.map { group in
            ThemedSheetAction(title: (group == activeGroup ? "✓ " : "") + group, icon: "folder", background: group == activeGroup ? Theme.pinkSoft : Theme.palette.lavenderSoft) { [weak self] in
                self?.activeGroup = group
                self?.tableView.reloadData()
            }
        }
        present(ThemedActionSheetController(title: "选择账号分组", actions: actions), animated: false)
    }
}

final class SlotAccountPickerViewController: UITableViewController {
    var onSelect: ((SnowAccount) -> Void)?
    private let accounts: [SnowAccount]
    private let selectedIDs: Set<UUID>
    init(accounts: [SnowAccount], selected: [SnowAccount]) {
        self.accounts = accounts
        self.selectedIDs = Set(selected.map(\.id))
        super.init(style: .insetGrouped)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "选择槽位账号"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancel))
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "SlotAccount")
    }
    @objc private func cancel() { dismiss(animated: true) }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { accounts.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SlotAccount", for: indexPath)
        let account = accounts[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = account.name
        content.secondaryText = selectedIDs.contains(account.id) ? "已在其他槽位" : account.group
        cell.contentConfiguration = content
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { onSelect?(accounts[indexPath.row]) }
}
