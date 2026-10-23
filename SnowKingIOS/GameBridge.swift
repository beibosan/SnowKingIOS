import Foundation
import UIKit
import WebKit
import CryptoKit

import Photos
/// Small, versioned bridge used by the bundled game page.
/// It intentionally exposes only compatibility methods needed by the current
/// assets; unsupported commands are reported instead of invoking arbitrary JS.
final class GameBridge: NSObject, WKScriptMessageHandler {
    var requestImportFile: (() -> Void)?
    weak var webView: WKWebView?
    weak var owner: GameViewController?
    private(set) var reports: [[String: Any]] = []
    private struct PendingSave {
        let createdAt: Date
        var kind: String
        var fileName: String
        var mimeType: String
        var chunks: [String]
        var characterCount: Int
    }
    private var pendingSaves: [String: PendingSave] = [:]
    private let saveQueue = DispatchQueue(label: "snowking.exports", qos: .utility)
    private let maximumPendingSaveCharacters = 64 * 1024 * 1024

    static var exportDirectoryURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SnowKingExports", isDirectory: true)
    }

    static var exportStorageSize: Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: exportDirectoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    init(owner: GameViewController? = nil) {
        self.owner = owner
        super.init()
    }

    func userScript(for account: SnowAccount, isolateAccountStorage: Bool = false, enableIPadLandscapeRotation: Bool = true) -> WKUserScript {
        let bin = escapeJSON(account.binData ?? "")
        let contentHash = hash(account.binData ?? "")
        let decoded = escapeJSON(validDecodedLoginInfo(for: account, contentHash: contentHash))
        let accountID = escapeJSON(account.id.uuidString)
        let name = escapeJSON(account.name)
        let serverId = escapeJSON(account.serverId ?? "")
        let escapedContentHash = escapeJSON(contentHash)
        let lineupData = encodeJSONObject(account.lineupData ?? [:])
        let isolatedStorage = isolateAccountStorage ? "true" : "false"
        let ipadLandscapeRotation = enableIPadLandscapeRotation ? "true" : "false"
        let deviceID = escapeJSON(UIDevice.current.identifierForVendor?.uuidString ?? account.id.uuidString)
        let maxConcurrency = isolateAccountStorage ? 4 : 8
        let maxRequestsPerFrame = isolateAccountStorage ? 2 : 4
        let soundMuted = UserDefaults.standard.bool(forKey: "sound_muted") ? "true" : "false"
        let resourceCacheEnabled = (UserDefaults.standard.object(forKey: "cache_enabled") == nil || UserDefaults.standard.bool(forKey: "cache_enabled"))
            ? "true" : "false"
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        let escapedAppBuild = escapeJSON(appBuild)
        let resourceCacheName = escapeJSON("game-cache-v\(appBuild)")
        let manifestCacheStale = UserDefaults.standard.string(forKey: "snowking.resource-cache-build") == appBuild ? "false" : "true"
        let source = """
        (function () {
          window.__SNOWKING_ENABLE_IPAD_LANDSCAPE_ROTATION__ = \(ipadLandscapeRotation);
          window.__SNOWKING_FORCE_UPRIGHT_GAME__ = !window.__SNOWKING_ENABLE_IPAD_LANDSCAPE_ROTATION__;
          try {
            var modernIPad = navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1;
            if (window.__SNOWKING_ENABLE_IPAD_LANDSCAPE_ROTATION__ && modernIPad && !/ipad|mobile/i.test(navigator.userAgent || '')) {
              var originalUserAgent = navigator.userAgent || '';
              Object.defineProperty(navigator, 'userAgent', {
                configurable: true,
                get: function () { return originalUserAgent + ' iPad Mobile'; }
              });
              window.__SNOWKING_IPAD_UA_PATCHED__ = true;
            }
          } catch (_) {}
          window.__SNOWKING_NATIVE_BRIDGE_VERSION__ = 1;
          window.__snowkingSetNativeAccountContext = function (context) {
            context = context || {};
            window.__SNOWKING_ACCOUNT_ID__ = String(context.id || '');
            window.__SNOWKING_BIN_DATA__ = String(context.binData || '');
            window.__SNOWKING_DECODED_LOGIN_INFO__ = String(context.decodedLoginInfo || '');
            window.__SNOWKING_ACCOUNT_NAME__ = String(context.name || '');
            window.__SNOWKING_SERVER_ID__ = String(context.serverId || '');
            window.__SNOWKING_BIN_HASH__ = String(context.binHash || '');
            window.__SNOWKING_LINEUP_DATA__ = context.lineupData || {};
            window.__SNOWKING_CURRENT_ACCOUNT__ = {
              id: window.__SNOWKING_ACCOUNT_ID__,
              name: window.__SNOWKING_ACCOUNT_NAME__,
              serverId: window.__SNOWKING_SERVER_ID__,
              binHash: window.__SNOWKING_BIN_HASH__
            };
            window.__SNOWKING_SCRIPT_ACCOUNT__ = window.__SNOWKING_CURRENT_ACCOUNT__;
            window.snowKingCurrentAccount = window.__SNOWKING_CURRENT_ACCOUNT__;
            try {
              window.dispatchEvent(new CustomEvent('snowking:account-changed', { detail: window.__SNOWKING_CURRENT_ACCOUNT__ }));
            } catch (_) {}
            return window.__SNOWKING_CURRENT_ACCOUNT__;
          };
          window.__snowkingSetNativeAccountContext({
            id: \(accountID),
            binData: \(bin),
            decodedLoginInfo: \(decoded),
            name: \(name),
            serverId: \(serverId),
            binHash: \(escapedContentHash),
            lineupData: \(lineupData)
          });
          function post(command, args) {
            try {
              var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.birdKingNative;
              if (h) h.postMessage({ id: command + '-' + Date.now(), command: command, args: args || {} });
              if (command === 'console') {
                var c = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.heguangConsole;
                if (c) c.postMessage(args || {});
              }
            } catch (_) {}
          }
          function safeExportName(value) {
            var name = String(value || 'SnowKing-export.bin').replace(/[\\\\/:*?"<>|\\x00-\\x1f]/g, '_');
            return name.slice(0, 120) || 'SnowKing-export.bin';
          }
          function exportPath(fileName) {
            return '文件 App/我的 iPhone/雪花之王/SnowKingExports/' + safeExportName(fileName);
          }
          function queuedResult(fileName) {
            return JSON.stringify({ ok: true, pending: true, path: exportPath(fileName) });
          }
          function queueNativeSave(kind, fileName, mimeType, data) {
            var value = String(data || '');
            var name = safeExportName(fileName);
            var mime = String(mimeType || 'application/octet-stream');
            if (value.length <= 262144) {
              post('savePayload', { kind: kind, fileName: name, mimeType: mime, data: value });
              return;
            }
            var saveId = 'save-' + Date.now() + '-' + Math.random().toString(36).slice(2);
            post('beginSave', { saveId: saveId, kind: kind, fileName: name, mimeType: mime });
            for (var offset = 0; offset < value.length; offset += 262144) {
              post('appendSave', { saveId: saveId, chunk: value.slice(offset, offset + 262144) });
            }
            post('finishSave', { saveId: saveId });
          }
          window.__BIRDKING_STARTUP_REPORT__ = function (level, event, detail) {
            post('startup_report', { level: level || 'info', event: event || '', detail: String(detail || '').slice(0, 320) });
          };
          window.__snowkingResourceCacheCallbacks = window.__snowkingResourceCacheCallbacks || {};
          window.__snowkingCompleteResourceCacheClear = function (requestId, result) {
            var callback = window.__snowkingResourceCacheCallbacks[requestId];
            if (!callback) return false;
            delete window.__snowkingResourceCacheCallbacks[requestId];
            callback(result || {});
            return true;
          };
          var bridge = {
            hasBin: function () { return !!window.__SNOWKING_BIN_DATA__; },
            getBinData: function () { return window.__SNOWKING_BIN_DATA__ || ''; },
            getBinBase64: function () { return window.__SNOWKING_BIN_DATA__ || ''; },
            getBinHex: function () {
              var b = window.__SNOWKING_BIN_DATA__ || '', out = '';
              try { var raw = atob(b); for (var i = 0; i < raw.length; i++) out += ('0' + raw.charCodeAt(i).toString(16)).slice(-2); } catch (_) {}
              return out;
            },
            getBinName: function () { return window.__SNOWKING_ACCOUNT_NAME__ || ''; },
            getAccountName: function () { return window.__SNOWKING_ACCOUNT_NAME__ || ''; },
            getBinContentHash: function () { return window.__SNOWKING_BIN_HASH__ || ''; },
            getAccountId: function () { return window.__SNOWKING_ACCOUNT_ID__ || ''; },
            getServerId: function () { return window.__SNOWKING_SERVER_ID__ || ''; },
            isAccountStorageIsolated: function () { return \(isolatedStorage); },
            getAccountStorageNamespace: function () { return \(isolatedStorage) ? (window.__SNOWKING_BIN_HASH__ || window.__SNOWKING_ACCOUNT_ID__ || '') : ''; },
            getCurrentAccount: function () { try { return JSON.stringify(window.__SNOWKING_CURRENT_ACCOUNT__ || {}); } catch (_) { return '{}'; } },
            getDecodedLoginInfo: function () { return window.__SNOWKING_DECODED_LOGIN_INFO__ || ''; },
            getDecodedLoginInfoJson: function () { return window.__SNOWKING_DECODED_LOGIN_INFO__ || ''; },
            cacheDecodedData: function (value) {
              window.__SNOWKING_DECODED_LOGIN_INFO__ = String(value || '');
              post('cacheDecodedData', {
                value: window.__SNOWKING_DECODED_LOGIN_INFO__,
                binHash: window.__SNOWKING_BIN_HASH__ || '',
                accountId: window.__SNOWKING_ACCOUNT_ID__ || ''
              });
              return true;
            },
            getNativeBundleVersJson: function () {
              try {
                var settings = window._CCSettings || {};
                return JSON.stringify(settings.bundleVers || {});
              } catch (_) {
                return '';
              }
            },
            getAppBuild: function () { return \(escapedAppBuild); },
            getResourceCacheName: function () { return \(resourceCacheName); },
            isManifestCacheStale: function () { return \(manifestCacheStale); },
            markManifestCacheCurrent: function () { post('markManifestCacheCurrent', { build: \(escapedAppBuild) }); return true; },
            isResourceCacheEnabled: function () { return (resourceCacheEnabled); },
            clearAllResourceCaches: function () {
              var clearWebCaches = window.caches && window.caches.keys
                ? window.caches.keys().then(function (names) {
                    return Promise.all(names.filter(function (name) {
                      var value = String(name || '').toLowerCase();
                      return value.indexOf('game-cache') === 0 || value.indexOf('snowking') === 0;
                    }).map(function (name) { return window.caches.delete(name).catch(function () { return false; }); }));
                  }).catch(function () { return []; })
                : Promise.resolve([]);
              return clearWebCaches.then(function () {
                try { localStorage.removeItem('_yunqi_manifest_cache'); localStorage.removeItem('_snowking_resource_cache_build'); } catch (_) {}
                return new Promise(function (resolve) {
                  var requestId = 'cache-' + Date.now() + '-' + Math.random().toString(36).slice(2);
                  var timer = setTimeout(function () {
                    delete window.__snowkingResourceCacheCallbacks[requestId];
                    resolve({ ok: false, timeout: true });
                  }, 20000);
                  window.__snowkingResourceCacheCallbacks[requestId] = function (result) {
                    clearTimeout(timer);
                    resolve(result || { ok: true });
                  };
                  post('clearResourceCaches', { requestId: requestId });
                });
              });
            },
            getDeviceId: function () { return \(deviceID); },
            getLoginInjectScript: function () { return ''; },
            isSoundMuted: function () { return \(soundMuted); },
            getRoleToken: function () { return ''; },
            refreshSession: function () { return false; },
            setClipboardData: function (value) { post('setClipboard', { text: String(value || '') }); return true; },
            copy: function (value) { post('setClipboard', { text: String(value || '') }); return true; },
            paste: function () { return ''; },
            saveImage: function (fileName, data) {
              queueNativeSave('saveImage', fileName, 'image/png', data);
              return queuedResult(fileName);
            },
            beginSaveImage: function () {
              var saveId = 'image-' + Date.now() + '-' + Math.random().toString(36).slice(2);
              post('beginSave', { saveId: saveId, kind: 'saveImage', fileName: '', mimeType: 'image/png' });
              return saveId;
            },
            appendSaveImage: function (saveId, chunk) {
              post('appendSave', { saveId: String(saveId || ''), chunk: String(chunk || '') });
              return true;
            },
            finishSaveImage: function (saveId, fileName) {
              post('finishSave', { saveId: String(saveId || ''), fileName: safeExportName(fileName) });
              return queuedResult(fileName);
            },
            saveFile: function (fileName, data, mimeType) {
              queueNativeSave('saveFile', fileName, mimeType, data);
              return queuedResult(fileName);
            },
            saveDataUrl: function (fileName, dataUrl) {
              queueNativeSave('saveDataUrl', fileName, '', dataUrl);
              return queuedResult(fileName);
            },
             saveBase64: function (fileName, mimeType, base64Data) {
               queueNativeSave('saveBase64', fileName, mimeType, base64Data);
               return exportPath(fileName);
             },
             importFile: function () { post('importFile'); return true; },
             log: function (value) { post('console', { level: 'info', message: String(value || '') }); }
          };
          window.BinBridge = bridge;
          window.Bridge = bridge;
          window.ClipboardBridge = bridge;
          window.ClipboardHostBridge = bridge;
           window.AndroidBinBridge = bridge;
           window.DownloadBridge = bridge;
           window.yunqiBridge = bridge;
           window.__snowkingNativeImportFile = function (fileName, fileText) {
             try {
               var input = document.getElementById('hero-team-file-input');
               if (!input || typeof File !== 'function') return false;
               var file = new File([String(fileText || '')], String(fileName || 'import.json'), { type: 'application/json' });
               if (typeof DataTransfer === 'function') {
                 var transfer = new DataTransfer();
                 transfer.items.add(file);
                 input.files = transfer.files;
                 input.dispatchEvent(new Event('change', { bubbles: true }));
                 return true;
               }
             } catch (_) {}
             return false;
           };
           window.__snowkingInstallNativeImport = function () {
             var input = document.getElementById('hero-team-file-input');
             var button = document.getElementById('hero-team-import-btn');
             if (!input || !button || button.__snowkingNativeImportInstalled) return;
             button.__snowkingNativeImportInstalled = true;
             input.style.display = 'none';
             button.addEventListener('click', function (event) {
               event.preventDefault();
               event.stopImmediatePropagation();
               bridge.importFile();
             }, true);
           };
           if (typeof MutationObserver === 'function' && document.body) {
             new MutationObserver(function () { window.__snowkingInstallNativeImport(); }).observe(document.body, { childList: true, subtree: true });
           }
           setTimeout(window.__snowkingInstallNativeImport, 500);
          window.ConcurrencyBridge = {
            getMaxConcurrency: function () { return \(maxConcurrency); },
            getMaxRequestsPerFrame: function () { return \(maxRequestsPerFrame); }
          };
          window.QVQ = window.QVQ || {};
          window.QVQ.saveImage = function (name, data) { try { return JSON.parse(bridge.saveImage(name, data)); } catch (_) { return { ok: false }; } };
          window.QVQ.saveFile = function (name, data, mime) { try { return JSON.parse(bridge.saveFile(name, data, mime)); } catch (_) { return { ok: false }; } };
          window.QVQ.saveDataUrl = function (name, data) { try { return JSON.parse(bridge.saveDataUrl(name, data)); } catch (_) { return { ok: false }; } };
          window.unsafeWindow = window;

          if (!window.__snowkingDownloadHookInstalled) {
            window.__snowkingDownloadHookInstalled = true;
            try {
              var savedBlobs = {};
              var originalCreateObjectURL = URL.createObjectURL;
              var originalRevokeObjectURL = URL.revokeObjectURL;
              URL.createObjectURL = function (object) {
                var url = originalCreateObjectURL.call(this, object);
                try { if (object instanceof Blob) savedBlobs[url] = object; } catch (_) {}
                return url;
              };
              URL.revokeObjectURL = function (url) {
                try { delete savedBlobs[url]; } catch (_) {}
                return originalRevokeObjectURL.call(this, url);
              };
              function saveDownloadAnchor(anchor) {
                var href = anchor && anchor.href || '';
                var fileName = anchor && anchor.download || '';
                if (href.indexOf('data:') === 0) {
                  bridge.saveDataUrl(fileName, href);
                  return true;
                }
                if (href.indexOf('blob:') === 0 && savedBlobs[href]) {
                  var reader = new FileReader();
                  reader.onload = function () { bridge.saveDataUrl(fileName, String(reader.result || '')); };
                  reader.readAsDataURL(savedBlobs[href]);
                  return true;
                }
                return false;
              }
              document.addEventListener('click', function (event) {
                var anchor = event.target && event.target.closest && event.target.closest('a[download]');
                if (anchor && saveDownloadAnchor(anchor)) {
                  event.preventDefault();
                  event.stopPropagation();
                }
              }, true);
              var originalAnchorClick = HTMLAnchorElement.prototype.click;
              HTMLAnchorElement.prototype.click = function () {
                if (saveDownloadAnchor(this)) return;
                return originalAnchorClick.call(this);
              };
            } catch (error) {
              console.error('[SnowKing Save] download hook failed', error);
            }
          }
        })();
        """
        return WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true)
    }

    func sessionUpdateScript(for account: SnowAccount) -> String {
        let bin = escapeJSON(account.binData ?? "")
        let contentHash = hash(account.binData ?? "")
        let decoded = escapeJSON(validDecodedLoginInfo(for: account, contentHash: contentHash))
        let accountID = escapeJSON(account.id.uuidString)
        let name = escapeJSON(account.name)
        let serverId = escapeJSON(account.serverId ?? "")
        let escapedContentHash = escapeJSON(contentHash)
        let lineupData = encodeJSONObject(account.lineupData ?? [:])
        return """
        (function () {
          var context = {
            id: \(accountID),
            binData: \(bin),
            decodedLoginInfo: \(decoded),
            name: \(name),
            serverId: \(serverId),
            binHash: \(escapedContentHash),
            lineupData: \(lineupData)
          };
          if (typeof window.__snowkingSetNativeAccountContext === 'function') {
            window.__snowkingSetNativeAccountContext(context);
          } else {
            window.__SNOWKING_ACCOUNT_ID__ = context.id;
            window.__SNOWKING_BIN_DATA__ = context.binData;
            window.__SNOWKING_DECODED_LOGIN_INFO__ = context.decodedLoginInfo;
            window.__SNOWKING_ACCOUNT_NAME__ = context.name;
            window.__SNOWKING_SERVER_ID__ = context.serverId;
            window.__SNOWKING_BIN_HASH__ = context.binHash;
            window.__SNOWKING_LINEUP_DATA__ = context.lineupData || {};
          }
          if (window.BinBridge && window.BinBridge.hasBin()) window.AndroidBinBridge = window.BinBridge;
          return !!window.AndroidBinBridge;
        })();
        """
    }

    func scriptUserScript(name: String, source: String, waitForAccount: Bool = false) -> WKUserScript {
        let scriptName = escapeJSON(name)
        let scriptSource = escapeJSON(source)
        let launch = waitForAccount ? "waitForAccountThenEnqueue();" : "enqueueAfterPageLoad();"
        let wrapped = """
        (function () {
          var scriptStarted = false;
          function runSnowKingScript() {
            if (scriptStarted) return;
            scriptStarted = true;
            window.__SNOWKING_ACTIVE_SCRIPT__ = \(scriptName);
            window.__SNOWKING_SCRIPT_ACCOUNT__ = window.__SNOWKING_CURRENT_ACCOUNT__ || null;
            try {
              (0, eval)(\(scriptSource));
              if (typeof window.__BIRDKING_STARTUP_REPORT__ === 'function') {
                window.__BIRDKING_STARTUP_REPORT__('info', 'script_loaded', \(scriptName));
              }
            } catch (error) {
              if (typeof window.__BIRDKING_STARTUP_REPORT__ === 'function') {
                window.__BIRDKING_STARTUP_REPORT__('error', 'script_failed', \(scriptName) + ': ' + String(error && error.message || error));
              }
              console.error('[SnowKingScript]', \(scriptName), error);
            }
          }
          function enqueueSnowKingScript() {
            window.__SNOWKING_SCRIPT_QUEUE__ = window.__SNOWKING_SCRIPT_QUEUE__ || [];
            window.__SNOWKING_SCRIPT_QUEUE__.push(runSnowKingScript);
            if (window.__SNOWKING_SCRIPT_QUEUE_RUNNING__) return;
            window.__SNOWKING_SCRIPT_QUEUE_RUNNING__ = true;
            (function drainQueue() {
              var task = window.__SNOWKING_SCRIPT_QUEUE__.shift();
              if (!task) {
                window.__SNOWKING_SCRIPT_QUEUE_RUNNING__ = false;
                return;
              }
              setTimeout(function () {
                try { task(); } finally { setTimeout(drainQueue, 180); }
              }, 0);
            })();
          }
          function enqueueAfterPageLoad() {
            var enqueue = function () { setTimeout(enqueueSnowKingScript, 500); };
            if (document.readyState === 'complete') enqueue();
            else window.addEventListener('load', enqueue, { once: true });
          }
          function waitForAccountThenEnqueue() {
            var ready = function () {
              return window.__yunqiNativeAccount ||
                !(window.AndroidBinBridge && window.AndroidBinBridge.hasBin && window.AndroidBinBridge.hasBin());
            };
            var begin = function () {
              if (ready()) { enqueueAfterPageLoad(); return; }
              var attempts = 0;
              var accountTimer = setInterval(function () {
                attempts += 1;
                if (ready() || attempts >= 300) {
                  clearInterval(accountTimer);
                  enqueueAfterPageLoad();
                }
              }, 100);
            };
            if (document.readyState === 'complete') begin();
            else window.addEventListener('load', begin, { once: true });
          }
          \(launch)
        })();
        """
        return WKUserScript(source: wrapped, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }

    func contentHash(for account: SnowAccount) -> String {
        hash(account.binData ?? "")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "birdKingNative" || message.name == "console" || message.name == "heguangConsole" else { return }
        let body = message.body as? [String: Any] ?? ["value": String(describing: message.body)]
        let command = body["command"] as? String ?? (message.name == "heguangConsole" ? "console" : message.name)
        let args = body["args"] as? [String: Any] ?? body
        switch command {
        case "startup_report":
            let level = args["level"] as? String ?? "info"
            let event = args["event"] as? String ?? "console"
            let detail = args["detail"] as? String ?? args["message"] as? String ?? ""
            appendReport(level: level, event: event, detail: detail)
            owner?.recordGameReport(level: level, event: event, detail: detail)
        case "console":
            let level = args["level"] as? String ?? "info"
            guard level == "error" else { return }
            let detail = args["detail"] as? String ?? args["message"] as? String ?? ""
            appendReport(level: level, event: "console", detail: detail)
            owner?.recordGameReport(level: level, event: "console", detail: detail)
        case "setClipboard":
            UIPasteboard.general.string = args["text"] as? String ?? ""
        case "cacheDecodedData":
            let value = args["value"] as? String ?? ""
            let binHash = args["binHash"] as? String ?? ""
            if let owner {
                owner.cacheDecodedLoginInfo(value, binHash: binHash)
            } else if !value.isEmpty, !binHash.isEmpty,
                      let rawID = args["accountId"] as? String,
                      let accountID = UUID(uuidString: rawID) {
                AccountStore.shared.updateDecodedLoginInfo(accountID: accountID, value: value, binHash: binHash)
            }
        case "saveLineupData":
            guard let rawID = args["accountId"] as? String,
                  let accountID = UUID(uuidString: rawID),
                  let key = args["key"] as? String,
                  let value = args["value"] as? String else { return }
            AccountStore.shared.updateLineupData(accountID: accountID, key: key, value: value)
        case "savePayload":
            scheduleSave(
                kind: args["kind"] as? String ?? "saveFile",
                fileName: args["fileName"] as? String ?? "",
                mimeType: args["mimeType"] as? String ?? "application/octet-stream",
                payload: args["data"] as? String ?? ""
            )
        case "beginSave":
            beginSave(args)
        case "appendSave":
            appendSave(args)
        case "finishSave":
            finishSave(args)
        case "clearResourceCaches":
            let requestID = args["requestId"] as? String ?? ""
            Self.clearResourceCaches { [weak self] before, after, urlCacheBytes in
                SnowLogger.info("Cache", "bridge cache clear recordsBefore=\(before) recordsAfter=\(after) urlCache=\(urlCacheBytes)")
                guard !requestID.isEmpty, let self else { return }
                let escapedID = self.escapeJSON(requestID)
                self.webView?.evaluateJavaScript("window.__snowkingCompleteResourceCacheClear && window.__snowkingCompleteResourceCacheClear(\(escapedID), {ok:true});")
            }
        case "importFile":
            requestImportFile?()
        default:
            owner?.recordGameReport(level: "debug", event: "unsupported_bridge_command", detail: command)
        }
    }

    private func escapeJSON(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let encoded = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(encoded.dropFirst().dropLast())
    }

    private func appendReport(level: String, event: String, detail: String) {
        reports.append(["level": level, "event": event, "detail": String(detail.prefix(320)), "date": Date().timeIntervalSince1970])
        if reports.count > 200 { reports.removeFirst(reports.count - 200) }
    }

    private func encodeJSONObject(_ value: [String: String]) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let encoded = String(data: data, encoding: .utf8) else { return "{}" }
        return encoded
    }

    private func beginSave(_ args: [String: Any]) {
        let saveID = args["saveId"] as? String ?? ""
        guard !saveID.isEmpty else { return }
        let now = Date()
        pendingSaves = pendingSaves.filter { now.timeIntervalSince($0.value.createdAt) < 120 }
        guard pendingSaves.count < 4 else { return }
        pendingSaves[saveID] = PendingSave(
            createdAt: now,
            kind: args["kind"] as? String ?? "saveFile",
            fileName: args["fileName"] as? String ?? "",
            mimeType: args["mimeType"] as? String ?? "application/octet-stream",
            chunks: [],
            characterCount: 0
        )
    }

    private func appendSave(_ args: [String: Any]) {
        let saveID = args["saveId"] as? String ?? ""
        let chunk = args["chunk"] as? String ?? ""
        guard var pending = pendingSaves[saveID],
              pending.characterCount + chunk.count <= maximumPendingSaveCharacters else {
            pendingSaves.removeValue(forKey: saveID)
            return
        }
        pending.chunks.append(chunk)
        pending.characterCount += chunk.count
        pendingSaves[saveID] = pending
    }

    private func finishSave(_ args: [String: Any]) {
        let saveID = args["saveId"] as? String ?? ""
        guard var pending = pendingSaves.removeValue(forKey: saveID) else { return }
        if let fileName = args["fileName"] as? String, !fileName.isEmpty { pending.fileName = fileName }
        scheduleSave(
            kind: pending.kind,
            fileName: pending.fileName,
            mimeType: pending.mimeType,
            payloadChunks: pending.chunks
        )
    }

    private func scheduleSave(kind: String, fileName: String, mimeType: String, payloadChunks: [String]) {
        saveQueue.async { [weak self] in
            do {
                let payload = payloadChunks.joined()
                let result = try Self.persist(kind: kind, fileName: fileName, mimeType: mimeType, payload: payload)
                DispatchQueue.main.async {
                    self?.recordSaveResult(level: "info", detail: result.path)
                    if kind == "saveImage" || kind == "saveDataUrl" {
                        self?.saveImageToPhotoLibrary(result)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.recordSaveResult(level: "error", detail: error.localizedDescription)
                }
            }
        }
    }

    private func scheduleSave(kind: String, fileName: String, mimeType: String, payloadChunks: [String]) {
        saveQueue.async { [weak self] in
            do {
                let payload = payloadChunks.joined()
                let result = try Self.persist(kind: kind, fileName: fileName, mimeType: mimeType, payload: payload)
                DispatchQueue.main.async {
                    self?.recordSaveResult(level: "info", detail: result.path)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.recordSaveResult(level: "error", detail: error.localizedDescription)
                }
            }
        }
    }

    private func recordSaveResult(level: String, detail: String) {
        appendReport(level: level, event: level == "info" ? "file_saved" : "file_save_failed", detail: detail)
        owner?.recordGameReport(level: level, event: level == "info" ? "file_saved" : "file_save_failed", detail: detail)
    }

    private static func persist(kind: String, fileName: String, mimeType: String, payload: String) throws -> URL {
        let decoded = try decodePayload(kind: kind, mimeType: mimeType, payload: payload)
        let directory = exportDirectoryURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let safeName = sanitizedFileName(fileName, mimeType: decoded.mimeType)
        let destination = uniqueURL(in: directory, fileName: safeName)
        try decoded.data.write(to: destination, options: .atomic)
        return destination
    }

    private static func decodePayload(kind: String, mimeType: String, payload: String) throws -> (data: Data, mimeType: String) {
        guard !payload.isEmpty else { throw CocoaError(.fileWriteUnknown) }
        if payload.hasPrefix("data:"), let comma = payload.firstIndex(of: ",") {
            let header = String(payload[payload.index(payload.startIndex, offsetBy: 5)..<comma])
            let body = String(payload[payload.index(after: comma)...])
            let declared = header.split(separator: ";").first.map(String.init) ?? mimeType
            if header.lowercased().contains(";base64") {
                guard let data = Data(base64Encoded: body, options: .ignoreUnknownCharacters) else { throw CocoaError(.fileReadCorruptFile) }
                return (data, normalizedMimeType(declared, fallback: mimeType))
            }
            let decoded = body.removingPercentEncoding ?? body
            return (Data(decoded.utf8), normalizedMimeType(declared, fallback: mimeType))
        }
        let normalized = normalizedMimeType(mimeType, fallback: mimeTypeForFileName("", fallback: "application/octet-stream"))
        let isText = normalized.hasPrefix("text/") || ["application/json", "application/xml", "application/javascript"].contains(normalized)
        if kind == "saveFile" && isText { return (Data(payload.utf8), normalized) }
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters), !data.isEmpty else {
            if kind == "saveFile" { return (Data(payload.utf8), normalized) }
            throw CocoaError(.fileReadCorruptFile)
        }
        return (data, normalized)
    }

    private static func sanitizedFileName(_ requested: String, mimeType: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|").union(.controlCharacters)
        var name = requested.components(separatedBy: invalid).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "雪花之王_\(Int(Date().timeIntervalSince1970))" }
        name = String(name.prefix(120))
        if URL(fileURLWithPath: name).pathExtension.isEmpty { name += extensionForMime(mimeType) }
        return name
    }

    private static func uniqueURL(in directory: URL, fileName: String) -> URL {
        let initial = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: initial.path) else { return initial }
        let extensionName = initial.pathExtension
        let base = initial.deletingPathExtension().lastPathComponent
        for index in 1..<10_000 {
            let suffix = extensionName.isEmpty ? "" : ".\(extensionName)"
            let candidate = directory.appendingPathComponent("\(base) (\(index))\(suffix)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent("\(base)-\(Int(Date().timeIntervalSince1970))")
    }

    private static func normalizedMimeType(_ value: String, fallback: String) -> String {
        let normalized = value.split(separator: ";").first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return normalized.contains("/") ? normalized : fallback
    }

    private static func mimeTypeForFileName(_ fileName: String, fallback: String) -> String {
        switch URL(fileURLWithPath: fileName).pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        case "json": return "application/json"
        case "txt": return "text/plain"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        default: return fallback
        }
    }

    private static func extensionForMime(_ mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/png": return ".png"
        case "image/jpeg": return ".jpg"
        case "image/webp": return ".webp"
        case "image/gif": return ".gif"
        case "application/json": return ".json"
        case "text/plain": return ".txt"
        case "application/pdf": return ".pdf"
        case "application/zip": return ".zip"
        default: return ".bin"
        }
    }

    private func hash(_ base64: String) -> String {
        let data = Data(base64Encoded: base64) ?? Data(base64.utf8)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func validDecodedLoginInfo(for account: SnowAccount, contentHash: String) -> String {
        guard account.decodedBinHash == contentHash else { return "" }
        return account.decodedLoginInfo ?? ""
    }

    deinit {
        owner = nil
    }

    static func clearResourceCaches(completion: @escaping (Int, Int, Int) -> Void) {
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeOfflineWebApplicationCache,
            WKWebsiteDataTypeFetchCache
        ]
        let store = WKWebsiteDataStore.default()
        store.fetchDataRecords(ofTypes: types) { before in
            let urlCacheBytes = URLCache.shared.currentDiskUsage + URLCache.shared.currentMemoryUsage
            URLCache.shared.removeAllCachedResponses()
            store.removeData(ofTypes: types, modifiedSince: .distantPast) {
                store.fetchDataRecords(ofTypes: types) { after in
                    DispatchQueue.main.async {
                        completion(before.count, after.count, urlCacheBytes)
                    }
                }
            }
        }
    }

    func completeImportFile(_ url: URL?) {
        guard let url else {
            SnowLogger.debug("Import", "native picker cancelled")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
                  !data.isEmpty, data.count <= 64 * 1024 * 1024,
                  let text = String(data: data, encoding: .utf8) else {
                SnowLogger.error("Import", "unable to read UTF-8 file or file exceeds 64 MB: \(url.lastPathComponent)")
                return
            }
            let name = self?.escapeJSON(url.lastPathComponent) ?? "\"import.json\""
            let body = self?.escapeJSON(text) ?? "\"\""
            DispatchQueue.main.async {
                self?.webView?.evaluateJavaScript("window.__snowkingNativeImportFile && window.__snowkingNativeImportFile(\(name),\(body));") { result, error in
                    if let error {
                        SnowLogger.error("Import", "JavaScript import failed: \(error.localizedDescription)")
                    } else if (result as? Bool) != true {
                        SnowLogger.error("Import", "JavaScript import rejected \(url.lastPathComponent)")
                    } else {
                        SnowLogger.info("Import", "imported \(url.lastPathComponent) bytes=\(data.count)")
                    }
                }
            }
        }
    }

    private func saveImageToPhotoLibrary(_ fileURL: URL) {
        let saveAsset: () -> Void = { [weak self] in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
            }) { saved, error in
                DispatchQueue.main.async {
                    if let error {
                        self?.owner?.recordGameReport(level: "error", event: "photo_save_failed", detail: error.localizedDescription)
                    } else if saved {
                        self?.owner?.recordGameReport(level: "info", event: "photo_saved", detail: fileURL.lastPathComponent)
                    }
                }
            }
        }

        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            saveAsset()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                DispatchQueue.main.async {
                    if status == .authorized || status == .limited {
                        saveAsset()
                    } else {
                        self.owner?.recordGameReport(level: "error", event: "photo_save_denied", detail: "photo library permission denied")
                    }
                }
            }
        default:
            owner?.recordGameReport(level: "error", event: "photo_save_denied", detail: "photo library permission denied")
        }
    }
}
