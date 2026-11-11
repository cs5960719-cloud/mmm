import UIKit
import WebKit

@MainActor
final class GameSession: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    let webView: WKWebView
    private let bundle: GameBundle
    private let token = UUID().uuidString
    private var expired = false
    private var expiryTimer: Timer?
    private var lastRestart = Date.distantPast
    private var closed = false
    private var foundGameFrame = false
    var status = "正在进入游戏…" { didSet { onChange?() } }
    var onChange: (() -> Void)?
    var onRestart: (() -> Void)?
    weak var presenter: UIViewController?

    init(account: Account, bundle: GameBundle) throws {
        self.bundle = bundle
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: account.id)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = self
        webView.uiDelegate = self
        let controller = configuration.userContentController
        let bridge = try Self.resource("bridge", extension: "js")
            .replacingOccurrences(of: "__IOS_SESSION_TOKEN__", with: Self.quote(token))
        let entry = try Self.resource("game-start", extension: "js")
            .replacingOccurrences(of: "__CDK_SERVER__", with: Self.quote(bundle.login.server))
            .replacingOccurrences(of: "__CDK_ROLE__", with: Self.quote(bundle.login.role_id ?? ""))
        controller.add(self, name: "iosSlot")
        // Public WebKit APIs inject into every frame, including the game's cross-origin frame.
        controller.addUserScript(WKUserScript(source: bridge, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        controller.addUserScript(WKUserScript(source: entry, injectionTime: .atDocumentEnd, forMainFrameOnly: false))
    }

    func start() throws {
        webView.load(URLRequest(url: try APIClient.gameURL(bundle.login.url)))
        expiryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkExpiry() }
        }
    }

    func startFixture(index: Int) {
        let html = (try? Self.resource("fixture", extension: "html")) ?? "Fixture missing"
        webView.loadHTMLString(html.replacingOccurrences(of: "__SLOT__", with: String(index)),
                               baseURL: URL(string: "https://fixture.invalid"))
    }

    func close() {
        guard !closed else { return }
        closed = true
        expiryTimer?.invalidate()
        expiryTimer = nil
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "iosSlot")
        webView.configuration.userContentController.removeAllUserScripts()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
        webView.removeFromSuperview()
        onChange = nil
        onRestart = nil
    }

    private func checkExpiry() {
        guard !closed, !expired, Date().timeIntervalSince1970 >= Double(bundle.login.expire_at) else { return }
        expired = true
        webView.stopLoading()
        webView.loadHTMLString("<body style='background:#142032;color:white'>CDK 已到期，请续费后重新打开窗口。</body>", baseURL: nil)
        status = "CDK 已到期"
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard !closed, !expired, message.webView === webView,
              let body = message.body as? [String: String], body["token"] == token,
              let method = body["method"] else { return }
        switch method {
        case "entered", "needRole":
            foundGameFrame = true
            inject(into: message.frameInfo, needsRole: method == "needRole")
        case "restartGame":
            guard Date().timeIntervalSince(lastRestart) > 10 else { return }
            lastRestart = Date()
            onRestart?()
        case "fail":
            // Launcher frames may time out after a nested game frame has already entered.
            if !foundGameFrame { status = "进入游戏超时，可放大检查或点击重登" }
        case "health":
            switch body["detail"] {
            case "current": status = "挂机脚本已就绪"
            case "ready_apply": status = "功能更新就绪，请在游戏面板确认"
            case "ready_restart": status = "新版就绪，请重登更新"
            case "failed", "update_failed": status = "脚本获取失败，请检查游戏内提示"
            case "loading": status = "正在获取挂机模块…"
            case "legacy": status = "挂机脚本已注入"
            default: break
            }
        default: break
        }
    }

    private func inject(into frame: WKFrameInfo, needsRole: Bool) {
        let source = """
        (function(){
          if(window.__iosHelperInjected)return;
          \(bundle.script)
          window.__iosHelperInjected=true;
        })();
        """
        webView.evaluateJavaScript(source, in: frame, in: .page) { [weak self] result in
            guard let self, !self.closed, !self.expired else { return }
            switch result {
            case .success: self.status = needsRole ? "请放大窗口选择角色" : "脚本已注入，正在检查运行状态…"
            case .failure: self.status = "脚本注入失败，请重登后重试"
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard !closed, !expired, let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
        decisionHandler((try? APIClient.gameURL(url.absoluteString)) == nil ? .cancel : .allow)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { status = "页面加载失败，请重登" }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { status = "页面连接中断，请重登" }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        status = "页面被系统回收，请重登"
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, (try? APIClient.gameURL(url.absoluteString)) != nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // alert / confirm / prompt are used by the existing settings and module authorization UI.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let presenter, presenter.presentedViewController == nil else { completionHandler(); return }
        let alert = UIAlertController(title: "游戏提示", message: String(message.prefix(1000)), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler() })
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let presenter, presenter.presentedViewController == nil else { completionHandler(false); return }
        let alert = UIAlertController(title: "游戏确认", message: String(message.prefix(1000)), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        guard let presenter, presenter.presentedViewController == nil else { completionHandler(nil); return }
        let alert = UIAlertController(title: "游戏输入", message: String(prompt.prefix(1000)), preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText; $0.autocorrectionType = .no; $0.autocapitalizationType = .none }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { [weak alert] _ in completionHandler(alert?.textFields?.first?.text) })
        presenter.present(alert, animated: true)
    }

    static func quote(_ text: String) -> String {
        let data = try! JSONEncoder().encode(text)
        return String(decoding: data, as: UTF8.self)
    }

    private static func resource(_ name: String, extension ext: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
            throw ClientError.message("缺少内置资源：\(name)")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
