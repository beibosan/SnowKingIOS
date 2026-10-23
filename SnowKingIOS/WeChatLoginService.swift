import Foundation
import UIKit
import WebKit

final class WeChatLoginService: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    typealias QRHandler = (UIImage) -> Void
    typealias StatusHandler = (String) -> Void
    typealias ResultHandler = (Data, String) -> Void
    typealias RolesHandler = ([WeChatRole]) -> Void
    typealias FailureHandler = (String) -> Void

    struct WeChatRole {
        let id: String
        let name: String
        let serverId: String
        let level: String
    }

    private let session: URLSession
    private var task: URLSessionDataTask?
    private var pollTask: URLSessionDataTask?
    private var cancelled = false
    private var encoder: WKWebView?
    private var encodeCompletion: ((Result<Data, Error>) -> Void)?
    private var decoder: WKWebView?
    private var decodeCompletion: ((Result<[WeChatRole], Error>) -> Void)?
    private var onQR: QRHandler?
    private var onStatus: StatusHandler?
    private var onResult: ResultHandler?
    private var onRoles: RolesHandler?
    private var onFailure: FailureHandler?
    private var qrUUID = ""
    private var loginInfo: [String: Any]?
    private var loginNickname = ""
    private var pollFailures = 0

    private static let qrPage = "https://open.weixin.qq.com/connect/app/qrconnect?appid=wxfb0d5667e5cb1c44&bundleid=com.hortor.games.xyzw&scope=snsapi_base,snsapi_userinfo,snsapi_friend,snsapi_message&state=weixin"
    private static let loginURL = "https://comb-platform.hortorgames.com/comb-login-server/api/v1/login"
    private static let encodeHandler = "snowKingWxEncode"
    private static let decodeHandler = "snowKingWxDecode"

    override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpCookieStorage = .shared
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
        super.init()
    }

    func start(onQR: @escaping QRHandler, onStatus: @escaping StatusHandler,
               onResult: @escaping ResultHandler, onRoles: @escaping RolesHandler,
               onFailure: @escaping FailureHandler) {
        cancel()
        cancelled = false
        self.onQR = onQR
        self.onStatus = onStatus
        self.onResult = onResult
        self.onRoles = onRoles
        self.onFailure = onFailure
        pollFailures = 0
        status("正在获取微信二维码...")
        var request = URLRequest(url: URL(string: Self.qrPage)!)
        request.setValue(Self.wechatUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://open.weixin.qq.com/", forHTTPHeaderField: "Referer")
        task = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self, !self.cancelled else { return }
            if let error { self.fail("获取二维码失败：\(error.localizedDescription)"); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                self.fail("获取微信二维码失败：HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return
            }
            guard let data, let html = String(data: data, encoding: .utf8) else {
                self.fail("微信二维码页面无效"); return
            }
            do {
                let (imageURL, uuid) = try Self.parseQR(from: html)
                self.qrUUID = uuid
                self.downloadQR(imageURL)
            } catch { self.fail(error.localizedDescription) }
        }
        task?.resume()
    }

    func cancel() {
        cancelled = true
        task?.cancel(); pollTask?.cancel()
        task = nil; pollTask = nil
        encodeCompletion = nil
        decodeCompletion = nil
        releaseEncoder()
        releaseDecoder()
        loginInfo = nil
        loginNickname = ""
    }

    private func downloadQR(_ imageURL: URL) {
        var request = URLRequest(url: imageURL)
        request.setValue(Self.wechatUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self, !self.cancelled else { return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                self.fail("下载微信二维码失败：HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return
            }
            guard let data, let image = UIImage(data: data) else {
                self.fail("二维码图片解析失败：\(error?.localizedDescription ?? "未知错误")"); return
            }
            DispatchQueue.main.async { self.onQR?(image); self.status("请使用微信扫码并在手机上确认") }
            self.poll()
        }.resume()
    }

    private func poll() {
        guard !cancelled, !qrUUID.isEmpty else { return }
        let url = "https://open.weixin.qq.com/connect/l/qrconnect?uuid=\(qrUUID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? qrUUID)&f=url&_=" + String(Int(Date().timeIntervalSince1970 * 1000))
        var request = URLRequest(url: URL(string: url)!)
        request.setValue(Self.wechatUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://open.weixin.qq.com/", forHTTPHeaderField: "Referer")
        pollTask = session.dataTask(with: request) { [weak self] data, response, error in
            guard let self, !self.cancelled else { return }
            guard error == nil, let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode), let data else {
                self.pollFailures += 1
                let detail = error?.localizedDescription ?? "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                self.status("微信扫码状态查询失败（\(detail)），正在重试...")
                self.schedulePoll()
                return
            }
            self.pollFailures = 0
            let text = String(data: data, encoding: .utf8) ?? ""
            if let errorCode = Int(Self.capture("wx_errcode\\s*=\\s*(\\d+)", in: text) ?? "") {
                // WeChat returns 408 while this polling request is still waiting.
                // Only 402 means the QR code itself has expired.
                if errorCode == 402 { self.fail("二维码已过期，请重新获取"); return }
                if errorCode == 403 { self.fail("已取消扫码，请重新获取"); return }
            }
            let redirect = Self.capture("wx_redirecturl\\s*=\\s*['\"]([^'\"]+)", in: text)
            let code = redirect.flatMap { value in
                Self.capture("[?&]code=([^&'\\\"\\s]+)", in: value)
                    ?? Self.capture("^([^&'\\\"\\s]+)$", in: value)
            } ?? Self.capture("[?&]code=([^&'\\\"\\s]+)", in: text)
                ?? Self.capture("wx_code\\s*=\\s*['\"]([^'\"]+)", in: text)
            if let code, !code.isEmpty {
                self.loginNickname = Self.capture("wx_nickname\\s*=\\s*['\"]([^'\"]*)['\"]", in: text) ?? ""
                self.status("扫码成功，正在获取账号信息...")
                self.login(code: code.removingPercentEncoding ?? code)
                return
            }
            self.status("等待扫码确认...")
            self.schedulePoll()
        }
        pollTask?.resume()
    }

    private func schedulePoll() {
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.poll() }
    }

    private func login(code: String) {
        do {
            let payload = try makeLoginPayload(code: code)
            var request = URLRequest(url: URL(string: Self.loginURL + "?gameId=xyzwapp&timestamp=\(Int(Date().timeIntervalSince1970 * 1000))&version=android-4.2.1-cn-release&cryptVersion=1.1.0&gameTp=app&system=android&deviceUniqueId=DID-0e782e88-2f3b-4f5b-9020-47f5e5a5a026&packageName=com.hortor.games.xyzw")!)
            request.httpMethod = "POST"
            request.httpBody = payload.data(using: .utf8)
            request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue(Self.hortorUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("*/*", forHTTPHeaderField: "Accept")
            request.setValue("comb-platform.hortorgames.com", forHTTPHeaderField: "Host")
            request.setValue("keep-alive", forHTTPHeaderField: "Connection")
            request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
            request.setValue("https://open.weixin.qq.com", forHTTPHeaderField: "Origin")
            request.setValue("https://open.weixin.qq.com/", forHTTPHeaderField: "Referer")
            session.dataTask(with: request) { [weak self] data, response, error in
                guard let self, !self.cancelled else { return }
                do {
                    guard let data else { throw NSError(domain: "WeChatLogin", code: 1, userInfo: [NSLocalizedDescriptionKey: error?.localizedDescription ?? "登录无响应"]) }
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        let body = Self.responsePreview(data)
                        throw self.serviceError("登录接口 HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)\(body.isEmpty ? "" : "：\(body)")")
                    }
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let meta = json?["meta"] as? [String: Any]
                    let errorCode = (meta?["errCode"] as? NSNumber)?.intValue ?? Int(meta?["errCode"] as? String ?? "0") ?? 0
                    if errorCode != 0 {
                        throw NSError(domain: "WeChatLogin", code: errorCode, userInfo: [NSLocalizedDescriptionKey: meta?["errMsg"] as? String ?? "登录接口返回错误"])
                    }
                    let dataObject = json?["data"] as? [String: Any]
                    let comb = (dataObject?["combUser"] as? [String: Any])?["info"] as? [String: Any] ?? dataObject?["combUser"] as? [String: Any]
                    guard let comb, let encrypted = comb["encryptCombUser"] as? String, !encrypted.isEmpty,
                          let sign = comb["sign"] as? String, !sign.isEmpty else { throw NSError(domain: "WeChatLogin", code: 2, userInfo: [NSLocalizedDescriptionKey: "登录响应缺少账号凭据"]) }
                    let info: [String: Any] = ["encryptCombUser": encrypted, "timestamp": comb["timestamp"] ?? 0, "sign": sign]
                    self.loginInfo = info
                    self.status("正在读取微信下的账号列表...")
                    self.encodeBIN(combInfo: info, serverId: nil) { [weak self] result in
                        guard let self, !self.cancelled else { return }
                        switch result {
                        case .success(let baseBIN):
                            self.onResult?(baseBIN, self.loginNickname.isEmpty ? "微信账号" : self.loginNickname)
                            self.queryRoles(baseBIN)
                        case .failure(let error): self.fail("生成基础 BIN 失败：\(error.localizedDescription)")
                        }
                    }
                } catch { self.fail("微信登录失败：\(error.localizedDescription)") }
            }.resume()
        } catch { fail(error.localizedDescription) }
    }

    func encodeRole(_ role: WeChatRole, completion: @escaping ResultHandler) {
        guard let info = loginInfo else {
            completion(Data(), "微信登录信息已失效")
            return
        }
        encodeBIN(combInfo: info, serverId: role.serverId) { result in
            switch result {
            case .success(let data): completion(data, role.name.isEmpty ? "微信账号" : role.name)
            case .failure: completion(Data(), role.name.isEmpty ? "微信账号" : role.name)
            }
        }
    }

    private func encodeBIN(combInfo: [String: Any], serverId: String?, completion: @escaping (Result<Data, Error>) -> Void) {
        guard let sourceURL = Self.bundledResource(named: "launcher-auth-encode.iife", extension: "js", subdirectory: "GameAssets/wx"),
              let source = try? String(contentsOf: sourceURL, encoding: .utf8),
              let jsonData = try? JSONSerialization.data(withJSONObject: combInfo),
              let json = String(data: jsonData, encoding: .utf8)?.replacingOccurrences(of: "</", with: "<\\/") else {
            completion(.failure(serviceError("BIN 编码资源缺失"))); return
        }
        DispatchQueue.main.async {
            self.releaseEncoder()
            let configuration = WKWebViewConfiguration()
            configuration.userContentController.add(self, name: Self.encodeHandler)
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            self.encoder = webView
            self.encodeCompletion = { [weak self] result in
                guard let self else { return }
                self.encoder?.stopLoading(); self.encoder?.navigationDelegate = nil; self.encoder = nil
                completion(result)
            }
            let server = serverId.flatMap { value -> String? in
                guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) else { return nil }
                return String(data: data, encoding: .utf8)
            } ?? "null"
            let html = "<!doctype html><meta charset=\"utf-8\"><script>\(source)</script><script>try { var api=window.LauncherAuthEncode; if(api && api.LauncherAuthEncode) api=api.LauncherAuthEncode; if(!api || typeof api.encodeAuthBinFromCombUserInfoJson !== 'function') throw new Error('encode api missing'); var out=api.encodeAuthBinFromCombUserInfoJson(JSON.stringify(\(json)),\(server)); window.webkit.messageHandlers.\(Self.encodeHandler).postMessage(String(out||'')); } catch(e) { window.webkit.messageHandlers.\(Self.encodeHandler).postMessage('ERROR:'+String(e&&e.message||e)); }</script>"
            webView.loadHTMLString(html, baseURL: URL(string: "https://local.snowking/")!)
            self.perform(#selector(Self.encodeTimeout), with: nil, afterDelay: 20)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let value = message.body as? String else { return }
        if message.name == Self.encodeHandler {
            guard !value.isEmpty, !value.hasPrefix("ERROR:") else {
                let detail = value.hasPrefix("ERROR:") ? String(value.dropFirst(6)) : "BIN 编码结果为空"
                finishEncoding(.failure(serviceError(detail)))
                return
            }
            guard let data = Data(base64Encoded: value), !data.isEmpty else {
                finishEncoding(.failure(serviceError("BIN 数据格式错误")))
                return
            }
            finishEncoding(.success(data))
            return
        }

        guard message.name == Self.decodeHandler else { return }
        guard !value.isEmpty, !value.hasPrefix("ERROR:"), let data = value.data(using: .utf8) else {
            let detail = value.hasPrefix("ERROR:") ? String(value.dropFirst(6)) : "角色列表解码结果为空"
            finishDecoding(.failure(serviceError(detail)))
            return
        }
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data)
            let entries: [(String, Any)]
            if let object = jsonObject as? [String: Any] {
                entries = object.map { ($0.key, $0.value) }
            } else if let array = jsonObject as? [Any] {
                entries = array.enumerated().map { (String($0.offset), $0.element) }
            } else {
                entries = []
            }
            let roles = entries.compactMap { id, raw -> WeChatRole? in
                let role = (raw as? [String: Any]) ?? [:]
                let roleID = Self.stringValue(role["roleId"]) ?? Self.stringValue(role["role_id"]) ?? Self.stringValue(role["uid"]) ?? id
                let name = Self.stringValue(role["name"]) ?? Self.stringValue(role["roleName"]) ?? Self.stringValue(role["role_name"]) ?? Self.stringValue(role["nickName"]) ?? Self.stringValue(role["nickname"]) ?? ""
                let serverID = Self.stringValue(role["serverId"]) ?? Self.stringValue(role["server_id"]) ?? Self.stringValue(role["sid"]) ?? id
                let level = Self.stringValue(role["level"]) ?? Self.stringValue(role["lv"]) ?? ""
                return WeChatRole(id: roleID, name: name, serverId: serverID, level: level)
            }.filter { !$0.serverId.isEmpty || !$0.id.isEmpty }
            finishDecoding(.success(roles))
        } catch {
            finishDecoding(.failure(error))
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finishNavigationFailure(for: webView, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finishNavigationFailure(for: webView, error: error)
    }

    private func finishNavigationFailure(for webView: WKWebView, error: Error) {
        if webView === encoder {
            finishEncoding(.failure(error))
        } else if webView === decoder {
            finishDecoding(.failure(error))
        }
    }

    private func queryRoles(_ bin: Data) {
        var request = URLRequest(url: URL(string: "https://xxz-xyzw.hortorgames.com/login/serverlist?_seq=3")!)
        request.httpMethod = "POST"
        request.httpBody = bin
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue("application/octet-stream,*/*", forHTTPHeaderField: "Accept")
            request.setValue(Self.hortorUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("xxz-xyzw.hortorgames.com", forHTTPHeaderField: "Host")
            request.setValue("keep-alive", forHTTPHeaderField: "Connection")
            request.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("https://open.weixin.qq.com/", forHTTPHeaderField: "Referer")
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self, !self.cancelled else { return }
            guard let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                self.fail("读取微信账号失败：\(error?.localizedDescription ?? "服务器 HTTP \(status)")"); return
            }
            self.status("服务器已返回 \(data.count) 字节，正在解析账号...")
            self.decodeRoles(data)
        }.resume()
    }

    private func decodeRoles(_ response: Data) {
        guard let sourceURL = Self.bundledResource(named: "lz4_encryptor", extension: "js", subdirectory: "GameAssets"),
              let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            fail("角色列表解码资源缺失"); return
        }
        let encoded = response.base64EncodedString()
        DispatchQueue.main.async {
            self.releaseDecoder()
            let configuration = WKWebViewConfiguration()
            configuration.userContentController.add(self, name: Self.decodeHandler)
            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            self.decoder = webView
            self.decodeCompletion = { [weak self] result in
                guard let self else { return }
                self.decoder?.stopLoading(); self.decoder?.navigationDelegate = nil; self.decoder = nil
                switch result {
                case .success(let roles):
                    guard !roles.isEmpty else { self.fail("未读取到微信下的账号") ; return }
                    self.status("已读取到 \(roles.count) 个微信账号，请选择要导入的账号")
                    self.onRoles?(roles)
                case .failure(let error): self.fail("读取角色列表失败：\(error.localizedDescription)")
                }
            }
            // Use the same protocol entry point as the Android/web helper.
            // decMsg handles the response envelope and exposes getData(),
            // while the fallback keeps compatibility with older responses.
            let html = """
            <!doctype html><meta charset="utf-8">
            <script>window.globalThis=window;</script>
            <script>\(source)</script>
            <script>
            try {
              var b64='\(encoded)', bin=atob(b64), bytes=new Uint8Array(bin.length);
              for(var i=0;i<bin.length;i++) bytes[i]=bin.charCodeAt(i);
              if(!window.GameCrypto || !GameCrypto.bon) throw new Error('BON decoder missing');
              var raw, data;
              var auto=GameCrypto.getEncryptor?GameCrypto.getEncryptor('auto'):null;
              var decrypt=auto&&typeof auto.decrypt==='function'?function(value){return auto.decrypt(value);}:GameCrypto.lz4XorDecode;
              if(typeof GameCrypto.decMsg === 'function') {
                var msg=GameCrypto.decMsg(bytes.buffer, {
                  decrypt: decrypt,
                  encrypt: GameCrypto.lz4XorEncode
                });
                data = msg && typeof msg.getData === 'function' ? msg.getData() : msg;
                raw = msg && (msg._raw || msg.rawData || msg) || data;
              } else {
                var plain=decrypt(bytes);
                raw=GameCrypto.bon.decode(plain); data=raw;
              }
              // decMsg().getData() already decodes the typed body. Do not
              // replace it with a second untyped BON decode, which drops the
              // roles field for the current serverlist response.
              if(typeof GameCrypto.decMsg !== 'function' && raw&&raw.body&&GameCrypto.bon) data=GameCrypto.bon.decode(raw.body);
              // Convert only the small roles collection. The complete response also
              // contains the full server catalog and can be several megabytes.
              function toPlain(value, seen) {
                if(value===null || typeof value!=='object') return value;
                if(value instanceof ArrayBuffer) return Array.from(new Uint8Array(value));
                if(typeof ArrayBuffer!=='undefined' && ArrayBuffer.isView && ArrayBuffer.isView(value)) return Array.from(value);
                if(value instanceof Map) { var mapped={}; value.forEach(function(v,k){mapped[String(k)]=toPlain(v,seen)}); return mapped; }
                seen=seen||[]; if(seen.indexOf(value)>=0) return null; seen.push(value);
                if(Array.isArray(value)) return value.map(function(v){return toPlain(v,seen)});
                var out={}; Object.keys(value).forEach(function(k){ try { out[k]=toPlain(value[k],seen); } catch(_) {} });
                return out;
              }
              function candidate(value) {
                if(value===null || value===undefined) return null;
                var plain=toPlain(value);
                if(Array.isArray(plain) && plain.length) return plain;
                if(plain && typeof plain==='object' && Object.keys(plain).length) return plain;
                return null;
              }
              function findRoles(root) {
                var direct=[root&&root.roles, root&&root.roleList, root&&root.role_list,
                  root&&root.data&&root.data.roles, root&&root.data&&root.data.roleList,
                  root&&root.data&&root.data.data&&root.data.data.roles];
                for(var i=0;i<direct.length;i++){var found=candidate(direct[i]); if(found) return found;}
                var queue=[root], visited=[];
                while(queue.length){
                  var node=queue.shift();
                  if(!node||typeof node!=='object'||visited.indexOf(node)>=0) continue;
                  visited.push(node);
                  var keys=Object.keys(node);
                  for(var j=0;j<keys.length;j++){
                    var key=keys[j], value=node[key];
                    if(/^(roles?|role_list|roleList|players)$/i.test(key)){var found=candidate(value); if(found) return found;}
                    if(value&&typeof value==='object') queue.push(value);
                  }
                }
                return {};
              }
              var roles=findRoles(data);
              if(!roles || (typeof roles==='object' && !Object.keys(roles).length)) roles=findRoles(raw);
              roles=roles||{};
              if(Array.isArray(roles)){var listed={}; roles.forEach(function(v,i){var k=v&&(v.id||v.roleId||v.serverId||v.server_id)||String(i); listed[String(k)]=v}); roles=listed;}
              if(!Object.keys(roles).length){
                var fields=data&&typeof data==='object'?Object.keys(data).slice(0,12).join(','):'none';
                throw new Error('roles empty; response fields='+fields);
              }
              window.webkit.messageHandlers.\(Self.decodeHandler).postMessage(JSON.stringify(roles||{}));
            } catch(e) { window.webkit.messageHandlers.\(Self.decodeHandler).postMessage('ERROR:'+String(e&&e.message||e)); }
            </script>
            """
            webView.loadHTMLString(html, baseURL: URL(string: "https://local.snowking/")!)
            self.perform(#selector(Self.decodeTimeout), with: nil, afterDelay: 45)
        }
    }

    @objc private func decodeTimeout() {
        guard decoder != nil else { return }
        finishDecoding(.failure(serviceError("读取角色列表超时")))
    }

    @objc private func encodeTimeout() {
        guard encoder != nil else { return }
        finishEncoding(.failure(serviceError("生成 BIN 超时")))
    }

    private func finishEncoding(_ result: Result<Data, Error>) {
        guard let completion = encodeCompletion else { return }
        encodeCompletion = nil
        releaseEncoder()
        completion(result)
    }

    private func finishDecoding(_ result: Result<[WeChatRole], Error>) {
        guard let completion = decodeCompletion else { return }
        decodeCompletion = nil
        releaseDecoder()
        completion(result)
    }

    private func releaseEncoder() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(encodeTimeout), object: nil)
        guard let webView = encoder else { return }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.encodeHandler)
        webView.stopLoading()
        webView.navigationDelegate = nil
        encoder = nil
    }

    private func releaseDecoder() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(decodeTimeout), object: nil)
        guard let webView = decoder else { return }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Self.decodeHandler)
        webView.stopLoading()
        webView.navigationDelegate = nil
        decoder = nil
    }

    private func serviceError(_ message: String) -> NSError {
        NSError(domain: "WeChatLogin", code: 20, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func responsePreview(_ data: Data) -> String {
        guard let value = String(data: data.prefix(240), encoding: .utf8) else { return "" }
        return value.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeLoginPayload(code: String) throws -> String {
        let object: [String: Any] = ["gameId": "xyzwapp", "code": code, "gameTp": "app", "sysInfo": "{\"system\":\"Android\",\"hortorSDKVersion\":\"4.0.6-cn\",\"model\":\"22081212C\",\"brand\":\"Redmi\"}", "channel": "android", "appFrom": "com.tencent.mm", "noLogin": "2", "distinctId": "DID-a38175b7-14ce-4b36-aa89-3e092ea03ea6", "state": "hortor", "packageName": "com.hortor.games.xyzw", "tp": "app-we", "signPrint": "E6:F7:FE:A9:EC:8E:24:D0:4F:2A:32:50:28:78:E1:C5:5E:70:81:13"]
        let data = try JSONSerialization.data(withJSONObject: object)
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let tableURL = Self.bundledResource(named: "wx-cipher-table", extension: "json", subdirectory: "GameAssets/wx") else {
            throw NSError(domain: "WeChatLogin", code: 5, userInfo: [NSLocalizedDescriptionKey: "微信加密表未打包到应用中"])
        }
        guard let raw = try? String(contentsOf: tableURL, encoding: .utf8),
              let tableData = raw.data(using: .utf8),
              let table = (try? JSONSerialization.jsonObject(with: tableData, options: [.fragmentsAllowed])) as? String,
              !table.isEmpty else {
            throw NSError(domain: "WeChatLogin", code: 6, userInfo: [NSLocalizedDescriptionKey: "微信加密表格式无效"])
        }
        let base = Data(text.utf8).base64EncodedString()
        let shuffled = try transcode(table, times: 6)
        // Match Android's length / 3 extraction exactly.
        let keyLength = shuffled.count / 3
        let keyCharacters = stride(from: 0, to: keyLength, by: 1).map { offset in
            let index = shuffled.index(shuffled.startIndex, offsetBy: offset * 3)
            return shuffled[index]
        }
        let key = Array(String(keyCharacters).utf8)
        guard !key.isEmpty else { throw NSError(domain: "WeChatLogin", code: 6, userInfo: [NSLocalizedDescriptionKey: "微信加密表无效"]) }
        var out = [UInt8](); out.reserveCapacity(base.utf8.count)
        for (index, byte) in base.utf8.enumerated() { out.append(byte ^ key[(index + key.count / 2) % key.count]) }
        return Data(out).base64EncodedString()
    }

    private func transcode(_ value: String, times: Int) throws -> String {
        if times <= 0 { return value }
        guard value.count % 2 == 0 else { throw NSError(domain: "WeChatLogin", code: 7, userInfo: [NSLocalizedDescriptionKey: "微信加密表长度错误"]) }
        let index = value.index(value.startIndex, offsetBy: value.count / 2)
        let right = try transcode(String(value[index...]), times: times - 1)
        let left = try transcode(String(value[..<index]), times: times - 1)
        return right + left
    }

    private static func bundledResource(named name: String, extension ext: String, subdirectory: String) -> URL? {
        if let url = GameAssetStore.shared.url(forResource: name, withExtension: ext, subdirectory: subdirectory == "GameAssets" ? nil : subdirectory.replacingOccurrences(of: "GameAssets/", with: "")) {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory) {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        guard let root = Bundle.main.resourceURL else { return nil }
        let filename = "\(name).\(ext)"
        let nested = root.appendingPathComponent(subdirectory, isDirectory: true).appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: nested.path) { return nested }
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == filename {
            return url
        }
        return nil
    }

    private func status(_ value: String) { DispatchQueue.main.async { self.onStatus?(value) } }
    private func fail(_ value: String) { DispatchQueue.main.async { self.onFailure?(value) } }

    private static func parseQR(from html: String) throws -> (URL, String) {
        guard let image = capture("<img[^>]+auth_qrcode[^>]+src=['\\\"]([^'\\\"]+)", in: html) else { throw NSError(domain: "WeChatLogin", code: 8, userInfo: [NSLocalizedDescriptionKey: "未找到微信二维码"]) }
        let decoded = image.replacingOccurrences(of: "&amp;", with: "&")
        let absolute: URL? = decoded.hasPrefix("//") ? URL(string: "https:\(decoded)") : decoded.hasPrefix("/") ? URL(string: "https://open.weixin.qq.com\(decoded)") : URL(string: decoded)
        guard let absolute else { throw NSError(domain: "WeChatLogin", code: 9, userInfo: [NSLocalizedDescriptionKey: "二维码地址无效"]) }
        let uuid = absolute.pathComponents.last(where: { $0 != "/" && !$0.isEmpty }) ?? capture("(?:uuid=|qrconnect/|qrcode/)([A-Za-z0-9_-]+)", in: html)
        guard let uuid, !uuid.isEmpty else { throw NSError(domain: "WeChatLogin", code: 10, userInfo: [NSLocalizedDescriptionKey: "无法解析二维码 UUID"]) }
        return (absolute, uuid)
    }

    private static func capture(_ pattern: String, in value: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]), let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)), match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }

    private static let wechatUserAgent = "Mozilla/5.0 (Linux; Android 7.0; Mi-4c Build/NRD90M; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/53.0.2785.49 Mobile MQQBrowser/6.2 TBS/043632 Safari/537.36 MicroMessenger/6.6.1.1220(0x26060135) NetType/WIFI Language/zh_CN"
    private static let hortorUserAgent = "Mozilla/5.0 (Linux; Android 12; 23117RK66C Build/V417IR; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/95.0.4638.74 Mobile Safari/537.36"
}

final class WeChatRolePickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    var onImport: (([WeChatLoginService.WeChatRole]) -> Void)?
    var onCancel: (() -> Void)?

    private let roles: [WeChatLoginService.WeChatRole]
    private var selectedIndexes: Set<Int>
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let summaryLabel = UILabel()
    private let selectionLabel = UILabel()
    private let importButton = UIButton(type: .system)

    init(roles: [WeChatLoginService.WeChatRole]) {
        self.roles = roles
        selectedIndexes = Set(roles.indices)
        super.init(nibName: nil, bundle: nil)
        let contentHeight = min(CGFloat(680), max(CGFloat(430), CGFloat(190 + roles.count * 64)))
        preferredContentSize = CGSize(width: 560, height: contentHeight)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "选择微信角色"
        view.backgroundColor = Theme.page
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancelSelection))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "取消全选", style: .plain, target: self, action: #selector(toggleAll))
        buildView()
        updateSelectionState()
    }

    private func buildView() {
        let header = UIView()
        header.backgroundColor = Theme.page
        header.translatesAutoresizingMaskIntoConstraints = false

        summaryLabel.text = "已读取到 \(roles.count) 个微信角色"
        summaryLabel.textColor = Theme.ink
        summaryLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        selectionLabel.textColor = Theme.secondaryInk
        selectionLabel.font = .systemFont(ofSize: 13, weight: .regular)
        selectionLabel.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(summaryLabel)
        header.addSubview(selectionLabel)

        tableView.dataSource = self
        tableView.delegate = self
        tableView.rowHeight = 64
        tableView.backgroundColor = Theme.card
        tableView.separatorColor = Theme.line
        tableView.separatorInset = UIEdgeInsets(top: 0, left: 56, bottom: 0, right: 16)
        tableView.layer.cornerRadius = 8
        tableView.layer.borderWidth = 1
        tableView.layer.borderColor = Theme.line.cgColor
        tableView.clipsToBounds = true
        tableView.translatesAutoresizingMaskIntoConstraints = false

        let footer = UIView()
        footer.backgroundColor = Theme.card
        footer.translatesAutoresizingMaskIntoConstraints = false

        let divider = UIView()
        divider.backgroundColor = Theme.line
        divider.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("取消", for: .normal)
        cancelButton.setTitleColor(Theme.ink, for: .normal)
        cancelButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        cancelButton.backgroundColor = Theme.controlSoft
        cancelButton.layer.cornerRadius = 8
        cancelButton.addTarget(self, action: #selector(cancelSelection), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        importButton.setTitleColor(Theme.ink, for: .normal)
        importButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        importButton.backgroundColor = Theme.mintSoft
        importButton.layer.cornerRadius = 8
        importButton.addTarget(self, action: #selector(importSelection), for: .touchUpInside)
        importButton.translatesAutoresizingMaskIntoConstraints = false

        footer.addSubview(divider)
        footer.addSubview(cancelButton)
        footer.addSubview(importButton)
        view.addSubview(header)
        view.addSubview(tableView)
        view.addSubview(footer)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 76),
            summaryLabel.topAnchor.constraint(equalTo: header.topAnchor, constant: 14),
            summaryLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            summaryLabel.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            selectionLabel.topAnchor.constraint(equalTo: summaryLabel.bottomAnchor, constant: 5),
            selectionLabel.leadingAnchor.constraint(equalTo: summaryLabel.leadingAnchor),
            selectionLabel.trailingAnchor.constraint(equalTo: summaryLabel.trailingAnchor),

            tableView.topAnchor.constraint(equalTo: header.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            tableView.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -12),

            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 76),
            divider.topAnchor.constraint(equalTo: footer.topAnchor),
            divider.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: footer.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
            cancelButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16),
            cancelButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),
            importButton.leadingAnchor.constraint(equalTo: cancelButton.trailingAnchor, constant: 10),
            importButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -16),
            importButton.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            importButton.heightAnchor.constraint(equalTo: cancelButton.heightAnchor),
            importButton.widthAnchor.constraint(equalTo: cancelButton.widthAnchor, multiplier: 1.7)
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { roles.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let identifier = "WechatRoleCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: identifier) ?? UITableViewCell(style: .subtitle, reuseIdentifier: identifier)
        let role = roles[indexPath.row]
        cell.backgroundColor = Theme.card
        cell.textLabel?.text = role.name.isEmpty ? "未命名角色" : role.name
        cell.textLabel?.textColor = Theme.ink
        cell.textLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        var details: [String] = []
        if !role.id.isEmpty { details.append("角色 ID \(role.id)") }
        if !role.serverId.isEmpty { details.append("\(role.serverId) 服") }
        if !role.level.isEmpty, role.level != "0" { details.append("Lv.\(role.level)") }
        cell.detailTextLabel?.text = details.joined(separator: "  ·  ")
        cell.detailTextLabel?.textColor = Theme.secondaryInk
        cell.detailTextLabel?.font = .systemFont(ofSize: 12)
        cell.imageView?.image = Theme.symbol("person.crop.circle", size: 22, weight: .medium)?.withRenderingMode(.alwaysTemplate)
        cell.imageView?.tintColor = Theme.currentAccent
        cell.accessoryType = selectedIndexes.contains(indexPath.row) ? .checkmark : .none
        cell.tintColor = Theme.currentAccent
        cell.selectionStyle = .none
        cell.accessibilityLabel = [cell.textLabel?.text, cell.detailTextLabel?.text].compactMap { $0 }.joined(separator: ", ")
        cell.accessibilityValue = selectedIndexes.contains(indexPath.row) ? "已选择" : "未选择"
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if selectedIndexes.contains(indexPath.row) {
            selectedIndexes.remove(indexPath.row)
        } else {
            selectedIndexes.insert(indexPath.row)
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        updateSelectionState()
    }

    private func updateSelectionState() {
        let count = selectedIndexes.count
        selectionLabel.text = count == roles.count ? "已全部选择，可取消不需要导入的角色" : "已选择 \(count) / \(roles.count) 个角色"
        importButton.setTitle("导入选中（\(count)）", for: .normal)
        importButton.isEnabled = count > 0
        importButton.alpha = count > 0 ? 1 : 0.45
        navigationItem.rightBarButtonItem?.title = count == roles.count ? "取消全选" : "全选"
    }

    @objc private func toggleAll() {
        selectedIndexes = selectedIndexes.count == roles.count ? [] : Set(roles.indices)
        tableView.reloadData()
        updateSelectionState()
    }

    @objc private func cancelSelection() {
        onCancel?()
        dismiss(animated: true)
    }

    @objc private func importSelection() {
        let selected = selectedIndexes.sorted().map { roles[$0] }
        guard !selected.isEmpty else { return }
        onImport?(selected)
    }
}

final class WeChatScannerViewController: UIViewController {
    var onSaved: (() -> Void)?
    private let service = WeChatLoginService()
    private let qrImage = UIImageView()
    private let status = UILabel()
    private let nameField = UITextField()
    private let saveButton = UIButton(type: .system)
    private var pendingName = "微信账号"
    private var pendingRoles: [WeChatLoginService.WeChatRole] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.page
        title = "微信扫码导入"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(close))
        buildView()
        startScan()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || isMovingFromParent || navigationController?.isBeingDismissed == true {
            service.cancel()
        }
    }

    private func buildView() {
        qrImage.backgroundColor = Theme.card
        qrImage.layer.cornerRadius = 12
        qrImage.layer.borderWidth = 1
        qrImage.layer.borderColor = Theme.line.cgColor
        qrImage.contentMode = .scaleAspectFit
        qrImage.image = Theme.symbol("qrcode", size: 72, weight: .regular)
        qrImage.translatesAutoresizingMaskIntoConstraints = false

        status.text = "正在获取微信二维码..."
        status.textColor = Theme.secondaryInk
        status.font = .systemFont(ofSize: 13, weight: .semibold)
        status.textAlignment = .center
        status.numberOfLines = 0
        status.translatesAutoresizingMaskIntoConstraints = false

        nameField.placeholder = "账号名称（可选）"
        nameField.textColor = Theme.ink
        nameField.backgroundColor = Theme.card
        nameField.layer.cornerRadius = 10
        nameField.layer.borderWidth = 1
        nameField.layer.borderColor = Theme.line.cgColor
        nameField.setLeftPadding(12)
        nameField.translatesAutoresizingMaskIntoConstraints = false

        let refresh = UIButton(type: .system)
        refresh.setTitle("重新获取", for: .normal)
        refresh.setTitleColor(Theme.ink, for: .normal)
        refresh.backgroundColor = Theme.skySoft
        refresh.layer.cornerRadius = 10
        refresh.addTarget(self, action: #selector(startScan), for: .touchUpInside)
        refresh.translatesAutoresizingMaskIntoConstraints = false

        saveButton.setTitle("保存账号", for: .normal)
        saveButton.setTitleColor(Theme.ink, for: .normal)
        saveButton.backgroundColor = Theme.mintSoft
        saveButton.layer.cornerRadius = 10
        saveButton.alpha = 0.45
        saveButton.isEnabled = false
        saveButton.addTarget(self, action: #selector(saveAccount), for: .touchUpInside)
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        let actions = UIStackView(arrangedSubviews: [refresh, saveButton])
        actions.axis = .horizontal
        actions.spacing = 10
        actions.distribution = .fillEqually
        actions.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(qrImage); view.addSubview(status); view.addSubview(nameField); view.addSubview(actions)
        NSLayoutConstraint.activate([
            qrImage.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            qrImage.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            qrImage.widthAnchor.constraint(equalToConstant: 240),
            qrImage.heightAnchor.constraint(equalToConstant: 240),
            status.topAnchor.constraint(equalTo: qrImage.bottomAnchor, constant: 14),
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            nameField.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 16),
            nameField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            nameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            nameField.heightAnchor.constraint(equalToConstant: 46),
            actions.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 12),
            actions.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            actions.heightAnchor.constraint(equalToConstant: 46)
        ])
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func startScan() {
        pendingRoles = []
        saveButton.isEnabled = false
        saveButton.alpha = 0.45
        qrImage.image = Theme.symbol("qrcode", size: 72, weight: .regular)
        status.text = "正在获取微信二维码..."
        service.start(onQR: { [weak self] image in self?.qrImage.image = image }, onStatus: { [weak self] text in self?.status.text = text }, onResult: { [weak self] _, nickname in
            guard let self else { return }
            self.pendingName = nickname
            if self.nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { self.nameField.text = nickname }
        }, onRoles: { [weak self] roles in
            guard let self else { return }
            self.pendingRoles = roles
            self.saveButton.isEnabled = true
            self.saveButton.alpha = 1
            self.showRolePicker(roles)
        }, onFailure: { [weak self] error in
            self?.showFailure(error)
        })
    }

    private func showFailure(_ message: String) {
        status.text = message
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "微信账号读取失败", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "重新获取", style: .default) { [weak self] _ in
            self?.startScan()
        })
        alert.addAction(UIAlertAction(title: "关闭", style: .cancel))
        present(alert, animated: true)
    }

    @objc private func saveAccount() {
        guard !pendingRoles.isEmpty else { return }
        showRolePicker(pendingRoles)
    }

    private func showRolePicker(_ roles: [WeChatLoginService.WeChatRole]) {
        guard presentedViewController == nil else { return }
        let picker = WeChatRolePickerViewController(roles: roles)
        picker.onImport = { [weak self, weak picker] selected in
            picker?.dismiss(animated: true) {
                self?.importRoles(selected, index: 0)
            }
        }
        let navigation = UINavigationController(rootViewController: picker)
        navigation.preferredContentSize = picker.preferredContentSize
        if UIDevice.current.userInterfaceIdiom == .pad {
            navigation.modalPresentationStyle = .formSheet
        } else {
            navigation.modalPresentationStyle = .pageSheet
            if let sheet = navigation.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
            }
        }
        present(navigation, animated: true)
    }

    private func importRoles(_ roles: [WeChatLoginService.WeChatRole], index: Int) {
        guard index < roles.count else {
            status.text = "微信账号导入完成"
            onSaved?()
            dismiss(animated: true)
            return
        }
        status.text = "正在生成第 \(index + 1)/\(roles.count) 个账号..."
        service.encodeRole(roles[index]) { [weak self] data, _ in
            guard let self else { return }
            guard !data.isEmpty else {
                self.status.text = "第 \(index + 1) 个账号生成失败"
                return
            }
            self.saveRole(roles[index], data: data)
            self.importRoles(roles, index: index + 1)
        }
    }

    private func importRole(_ role: WeChatLoginService.WeChatRole) {
        status.text = "正在生成账号 BIN..."
        service.encodeRole(role) { [weak self] data, _ in
            guard let self else { return }
            guard !data.isEmpty else { self.status.text = "账号 BIN 生成失败，请重试"; return }
            self.saveRole(role, data: data)
            self.status.text = "微信账号已导入"
            self.onSaved?()
            self.dismiss(animated: true)
        }
    }

    private func saveRole(_ role: WeChatLoginService.WeChatRole, data: Data) {
        let custom = nameField.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = custom.isEmpty ? (role.name.isEmpty ? pendingName : role.name) : custom
        let suffix = role.serverId.isEmpty ? "" : "-\(role.serverId)"
        AccountStore.shared.addImported(name: base + suffix, data: data, fileName: safeFileName(base + suffix) + ".bin", serverId: role.serverId.isEmpty ? nil : role.serverId)
    }

    private func safeFileName(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let result = value.components(separatedBy: invalid).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? "微信账号" : result
    }
}

private extension UITextField {
    func setLeftPadding(_ value: CGFloat) {
        leftView = UIView(frame: CGRect(x: 0, y: 0, width: value, height: 1))
        leftViewMode = .always
    }
}
