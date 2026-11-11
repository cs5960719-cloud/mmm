import UIKit
import WebKit

@MainActor
final class WorkspaceController: UIViewController {
    private let vault = AccountVault()
    private let api = APIClient()
    private var accounts: [Account] = []
    private var sessions: [Int: GameSession] = [:]
    private var pending: [Int: Task<Void, Never>] = [:]
    private var cards: [SlotCard] = []
    private let canvas = UIView()
    private let header = UIStackView()
    private let footer = UILabel()
    private var focusedSlotIndex: Int?
    private var storageReady = false
    private let fixtureMode = ProcessInfo.processInfo.arguments.contains("-local-fixture")

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.04, green: 0.07, blue: 0.12, alpha: 1)
        overrideUserInterfaceStyle = .dark
        header.axis = .horizontal
        header.spacing = 8
        header.alignment = .center
        let title = UILabel()
        title.text = "蓝胖子 · 苹果六开"
        title.font = .boldSystemFont(ofSize: 18)
        header.addArrangedSubview(title)
        header.addArrangedSubview(UIView())
        header.addArrangedSubview(button("全部打开") { [weak self] in self?.openAll() })
        header.addArrangedSubview(button("六宫格") { [weak self] in self?.focusedSlotIndex = nil; self?.view.setNeedsLayout() })
        view.addSubview(header)
        view.addSubview(canvas)
        footer.text = fixtureMode ? "本地测试模式 · 未连接真实游戏" : "保持 APP 前台运行 · 六开稳定性待真机验证"
        footer.font = .systemFont(ofSize: 11)
        footer.textColor = .secondaryLabel
        footer.textAlignment = .center
        footer.numberOfLines = 2
        view.addSubview(footer)
        for index in 0..<6 {
            let card = SlotCard(index: index)
            card.onEdit = { [weak self] in self?.edit(index) }
            card.onOpen = { [weak self] in self?.open(index) }
            card.onFocus = { [weak self] in
                guard let self else { return }
                self.focusedSlotIndex = self.focusedSlotIndex == index ? nil : index
                self.view.setNeedsLayout()
            }
            card.onMenu = { [weak self] in self?.menu(index) }
            cards.append(card)
            canvas.addSubview(card)
        }
        do {
            accounts = fixtureMode ? (0..<6).map { Account(name: "本地测试 \($0 + 1)", cdk: "ABCDEFGHIJKLMNOPQRSTUVWX") } : try vault.load()
            storageReady = true
            refresh()
            if fixtureMode { openAll() }
        } catch {
            accounts = (0..<6).map { _ in Account() }
            refresh()
            // Do not allow edits to overwrite an unreadable Keychain record.
            DispatchQueue.main.async { [weak self] in self?.notice("账号读取失败，请解锁后重启 APP。原数据未被覆盖。") }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let safe = view.safeAreaInsets
        let width = view.bounds.width - safe.left - safe.right
        header.frame = CGRect(x: safe.left + 12, y: safe.top + 4, width: width - 24, height: 44)
        footer.frame = CGRect(x: safe.left + 8, y: view.bounds.height - safe.bottom - 30, width: width - 16, height: 26)
        canvas.frame = CGRect(x: safe.left + 6, y: header.frame.maxY + 8, width: width - 12,
                              height: max(0, footer.frame.minY - header.frame.maxY - 14))
        let columns = canvas.bounds.width > canvas.bounds.height ? 3 : 2
        let rows = 6 / columns
        let gap: CGFloat = 6
        let cell = CGSize(width: max(0, (canvas.bounds.width - CGFloat(columns - 1) * gap) / CGFloat(columns)),
                          height: max(0, (canvas.bounds.height - CGFloat(rows - 1) * gap) / CGFloat(rows)))
        for index in 0..<6 {
            let card = cards[index]
            card.frame = CGRect(x: CGFloat(index % columns) * (cell.width + gap),
                                y: CGFloat(index / columns) * (cell.height + gap), width: cell.width, height: cell.height)
            card.isSlotFocused = focusedSlotIndex == index
        }
        // All six WebViews stay mounted. Enlarging a card covers the others; WebKit may still throttle them.
        if let focusedSlotIndex {
            cards[focusedSlotIndex].frame = canvas.bounds
            canvas.bringSubviewToFront(cards[focusedSlotIndex])
        }
    }

    func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = !sessions.isEmpty && UIApplication.shared.applicationState == .active
    }

    private func refresh() {
        guard accounts.count == 6 else { return }
        for index in 0..<6 {
            let card = cards[index]
            card.title.text = "\(index + 1) · \(accounts[index].name.isEmpty ? "空闲槽位" : accounts[index].name)"
            card.status.text = pending[index] != nil ? "正在登录并获取最新脚本…" : sessions[index]?.status ?? (accounts[index].cdk.isEmpty ? "先添加 CDK" : "已配置 · 未打开")
            card.openButton.setTitle(sessions[index] == nil ? "打开" : "重登", for: .normal)
            card.openButton.isEnabled = storageReady && pending[index] == nil
            card.editButton.isEnabled = storageReady && pending[index] == nil && sessions[index] == nil
            card.placeholder.isHidden = sessions[index] != nil
        }
        updateIdleTimer()
    }

    private func openAll() {
        guard storageReady else { return }
        for index in 0..<6 where !accounts[index].cdk.isEmpty && sessions[index] == nil { open(index) }
    }

    private func open(_ index: Int) {
        guard storageReady, pending[index] == nil else { return }
        guard !accounts[index].cdk.isEmpty else { edit(index); return }
        let account = accounts[index]
        pending[index] = Task { [weak self] in
            guard let self else { return }
            defer { self.pending[index] = nil; self.refresh() }
            do {
                let bundle: GameBundle
                if self.fixtureMode {
                    bundle = GameBundle(login: LoginReply(ok: true, url: "https://fixture.invalid", server: "1",
                        role_id: "1", expire_at: Int(Date().timeIntervalSince1970) + 3600), script: "window.__hangjiBuild='local-fixture';")
                } else {
                    bundle = try await self.api.open(cdk: account.cdk)
                }
                try Task.checkCancellation()
                let session = try GameSession(account: account, bundle: bundle)
                session.presenter = self
                session.onChange = { [weak self] in self?.refresh() }
                session.onRestart = { [weak self] in self?.open(index) }
                self.sessions[index]?.close()
                self.sessions[index] = session
                self.cards[index].attach(session.webView)
                if self.fixtureMode { session.startFixture(index: index + 1) } else { try session.start() }
                self.refresh()
            } catch is CancellationError { /* Closed by the user. */ }
            catch {
                guard !Task.isCancelled else { return }
                self.notice("窗口 \(index + 1)：\((error as? ClientError)?.localizedDescription ?? "打开失败，请重试")")
            }
        }
        refresh()
    }

    private func close(_ index: Int) {
        pending[index]?.cancel()
        sessions[index]?.close()
        sessions[index] = nil
        refresh()
    }

    private func edit(_ index: Int) {
        guard storageReady, sessions[index] == nil, pending[index] == nil, presentedViewController == nil else { return }
        let account = accounts[index]
        let alert = UIAlertController(title: "账号 \(index + 1)", message: "使用已激活 CDK；游戏账号和密码继续由原后台管理。", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "账号名称（可选）"; $0.text = account.name }
        alert.addTextField {
            $0.placeholder = account.cdk.isEmpty ? "请输入 CDK" : "留空保留原 CDK"
            $0.isSecureTextEntry = true
            $0.autocapitalizationType = .allCharacters
            $0.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self, weak alert] _ in
            guard let self, let fields = alert?.textFields else { return }
            do {
                let input = fields[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let cdk = try Account.normalize(input.isEmpty ? account.cdk : input)
                let name = String((fields[0].text ?? "").prefix(24))
                var next = self.accounts
                next[index] = Account(id: account.id, name: name.isEmpty ? "账号 \(index + 1)" : name, cdk: cdk)
                if !self.fixtureMode { try self.vault.save(next) }
                self.accounts = next
                self.refresh()
            } catch { self.notice((error as? ClientError)?.localizedDescription ?? "保存失败") }
        })
        present(alert, animated: true)
    }

    private func menu(_ index: Int) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "窗口 \(index + 1)", message: "关闭将停止此窗口的游戏和挂机。清除数据将同时退出此窗口的网页登录。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "关闭窗口", style: .destructive) { [weak self] _ in self?.close(index) })
        if pending[index] == nil {
            alert.addAction(UIAlertAction(title: "清除登录数据", style: .destructive) { [weak self] _ in self?.clear(index, delete: false) })
            alert.addAction(UIAlertAction(title: "删除账号及登录数据", style: .destructive) { [weak self] _ in self?.clear(index, delete: true) })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        present(alert, animated: true)
    }

    private func clear(_ index: Int, delete: Bool) {
        guard storageReady, pending[index] == nil else { return }
        close(index)
        let store = WKWebsiteDataStore(forIdentifier: accounts[index].id)
        pending[index] = Task { [weak self] in
            guard let self else { return }
            defer { self.pending[index] = nil; self.refresh() }
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
            if delete {
                do {
                    var next = self.accounts
                    next[index] = Account()
                    if !self.fixtureMode { try self.vault.save(next) }
                    self.accounts = next
                } catch { self.notice("删除账号失败，原 CDK 仍然保留") }
            }
        }
        refresh()
    }

    private func notice(_ text: String) {
        guard presentedViewController == nil else {
            footer.text = text
            return
        }
        let alert = UIAlertController(title: "蓝胖子", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }

    private func button(_ text: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(text, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }
}

@MainActor
final class SlotCard: UIView {
    let title = UILabel()
    let status = UILabel()
    let placeholder = UILabel()
    let openButton = UIButton(type: .system)
    let editButton = UIButton(type: .system)
    private let focusButton = UIButton(type: .system)
    private let menuButton = UIButton(type: .system)
    private let game = UIView()
    private weak var webView: WKWebView?
    var onEdit: (() -> Void)?
    var onOpen: (() -> Void)?
    var onFocus: (() -> Void)?
    var onMenu: (() -> Void)?
    var isSlotFocused = false { didSet { focusButton.setTitle(isSlotFocused ? "缩小" : "放大", for: .normal); setNeedsLayout() } }

    init(index: Int) {
        super.init(frame: .zero)
        accessibilityIdentifier = "slot-\(index + 1)"
        backgroundColor = UIColor(red: 0.08, green: 0.12, blue: 0.19, alpha: 1)
        layer.cornerRadius = 8
        clipsToBounds = true
        title.font = .boldSystemFont(ofSize: 13)
        status.font = .systemFont(ofSize: 10)
        status.textColor = .secondaryLabel
        status.numberOfLines = 2
        game.backgroundColor = .black
        game.clipsToBounds = true
        placeholder.text = "添加账号后打开游戏"
        placeholder.font = .systemFont(ofSize: 12)
        placeholder.textColor = .secondaryLabel
        placeholder.textAlignment = .center
        for child in [title, status, game, openButton, editButton, focusButton, menuButton] { addSubview(child) }
        game.addSubview(placeholder)
        let controls: [(UIButton, String, () -> Void)] = [
            (openButton, "打开", { [weak self] in self?.onOpen?() }),
            (editButton, "账号", { [weak self] in self?.onEdit?() }),
            (focusButton, "放大", { [weak self] in self?.onFocus?() }),
            (menuButton, "更多", { [weak self] in self?.onMenu?() })
        ]
        for (button, text, action) in controls {
            button.setTitle(text, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 12)
            button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func attach(_ webView: WKWebView) {
        self.webView = webView
        game.addSubview(webView)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        title.frame = CGRect(x: 7, y: 5, width: bounds.width - 14, height: 18)
        status.frame = CGRect(x: 7, y: 24, width: bounds.width - 14, height: 28)
        game.frame = CGRect(x: 0, y: 54, width: bounds.width, height: max(0, bounds.height - 88))
        placeholder.frame = game.bounds
        // Keep a phone-sized game viewport even inside a small six-grid cell.
        if let webView {
            let viewport = CGSize(width: 390, height: 700)
            let scale = min(game.bounds.width / viewport.width, game.bounds.height / viewport.height)
            webView.bounds = CGRect(origin: .zero, size: viewport)
            webView.transform = CGAffineTransform(scaleX: max(0.001, scale), y: max(0.001, scale))
            webView.center = CGPoint(x: game.bounds.midX, y: game.bounds.midY)
        }
        for (index, button) in [openButton, editButton, focusButton, menuButton].enumerated() {
            button.frame = CGRect(x: CGFloat(index) * bounds.width / 4, y: bounds.height - 33, width: bounds.width / 4, height: 33)
        }
    }
}
