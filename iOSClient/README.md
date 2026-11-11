# 蓝胖子苹果端 · 六窗口开发版

按现有安卓 CDK 登录、自动进区和挂机脚本流程开发。此目录是可交给 Mac/Xcode 构建的 iOS 原生工程，**尚未通过 Xcode 编译、签名或 iPhone 真机验收，也没有已发布 IPA**。当前开发电脑为 Windows。

## 已实现的代码

- 固定六个窗口；竖屏 2 列 × 3 行、横屏 3 列 × 2 行，支持单窗口放大及返回六宫格。
- 每个窗口使用独立、持久化的 `WKWebsiteDataStore`，以稳定 UUID 隔离 Cookie、LocalStorage 和网站数据。要求 **iOS/iPadOS 17.0 或更新系统**。
- 名称、CDK 和数据存储标识保存在设备 Keychain，使用 `WhenUnlockedThisDeviceOnly`；不把 CDK 写入网页、明文配置或工程。
- 原后台 `POST /api/login.php` 登录；使用返回的地址、区号、角色和到期时间。主节点网络/服务错误时尝试香港节点，业务拒绝不换节点重试。
- 每次打开、重登均实时获取 `/api/script_version.php` 和 `/api/script.php`，禁用客户端缓存并要求服务端 `Cache-Control: no-store`，校验 SHA-256、响应头哈希、大小及 UTF-8；不保存脚本离线副本。
- `Resources/game-start.js` 从安卓 `GameStartScript.java` 自动同步，保留自动选区、选角色和超时处理。原有游戏内挂机配置面板由远程脚本提供。
- 向各个 frame 注入入口脚本，使用 WebKit 的指定 frame 执行 API 把挂机脚本注入实际游戏 frame；支持 `CdkBridge.entered/needRole/fail/restartGame`。
- 展示模块加载及更新状态；模块后续检查沿用现有远程加载器，其接口请求继续使用 `no-store`。没有改动服务器或 CDN 配置。
- 重登会重新获取登录令牌和脚本；登录失败时保留原运行页面。关闭、清除登录数据、删除账号均有原生确认窗口。
- 前台有游戏窗口时禁止自动息屏；页面加载失败和系统回收页面时显示重登提示；客户端到期检查关闭对应页面。

“脚本就绪”表示脚本/模块装载完成，不代表游戏内每个挂机任务均已开启。具体开关继续使用原游戏内挂机面板。本版不伪造系统后台权限，不承诺后台、锁屏或六窗口稳定挂机。

## 在 Mac 上构建、安装

1. 把整个 `iOSClient` 文件夹复制到 Mac。已生成工程和入口资源，直接构建不需要 Python、Node、第三方库、CocoaPods 或 XcodeGen。
2. 使用 **Xcode 16 或更新版本**，打开 `Lanpangzi.xcodeproj`，选择共享 Scheme `Lanpangzi`。
3. 在应用 Target → Signing & Capabilities 中选择自己的 Team，把 Bundle Identifier `cn.duokai.ios` 改为自己可签名的唯一标识。测试 Target 的 Bundle Identifier 同样按需修改。
4. 把 iPhone 接到 Mac，解锁并信任电脑，按 Xcode 提示启用手机的开发者模式。选择真实设备后按 Run。
5. 如需导出安装包，在 Xcode 中 Product → Archive，使用自己账号有资格使用的开发、Ad Hoc 或其他分发方式。当前工程未配置分发证书和描述文件，未生成或上传安装包。

仅把 iPhone 接到 Windows，不能在这台机器上通过 Xcode 编译。Windows 上安装已经签名的 IPA 属于后续步骤，首先需要在 Mac 或已有云端 Mac 构建环境完成构建和签名。

## 只有 Windows：云端编译，再本机签名安装

已附 `.github/workflows/ios-build.yml`，使用 GitHub Actions 的 macOS 运行器。**目前只配置了本地流程，没有上传代码、创建远程仓库或触发云端构建；云端编译是否成功尚待实际运行。**

1. 在自己的 GitHub 账号下建一个私人仓库。只上传 `iOSClient` 文件夹里面的工程内容到仓库根目录，包含隐藏目录 `.github`；不要上传整个安卓项目、后台文件、CDK、服务器密钥或测试账号资料。
2. 确认仓库根目录存在 `.github/workflows/ios-build.yml` 和 `Lanpangzi.xcodeproj`。如果上传后工程仍在 `iOSClient` 子目录内，把 workflow 文件放到仓库根目录的 `.github/workflows/`，流程也可以识别子目录工程。
3. 在仓库 Actions 中打开 `Build iPhone test app`，手动点 Run workflow。GitHub 账号需要可使用 macOS Actions 的额度；按自己账号显示的额度和计费规则决定是否运行，不需要把 Apple ID 或证书传入这个流程。
4. 流程先运行原生模拟器测试，再编译真机应用。全部通过后，在该次运行的 Artifacts 下载 `Lanpangzi-unsigned-iphone-...`，解压得到 `Lanpangzi-unsigned.ipa`。**这是未签名安装包，不能直接点击安装。** 失败时先看对应构建日志及原生测试结果，不能认为已经得到可用 APP。
5. Windows 上可使用支持个人 Apple ID 签名的安装工具（例如 Sideloadly），从工具官方网站获取软件，选择已连接的 iPhone 和上述 IPA，在工具内自行输入 Apple ID 并完成签名安装。不要把 Apple ID 密码或验证码发到聊天或写入工程。
6. 按手机系统提示启用开发者模式、信任自己的开发者签名，然后打开 APP。免费个人签名通常只有 7 天有效期，到期需要重新签名，具体限制以 Apple 账号及安装工具的实际提示为准。

这条路径不需要自己拥有 Mac，也不需要先购买付费开发者账号。云端运行器仍然使用真正的 macOS/Xcode 完成编译；付费开发者分发和 TestFlight 属于之后的可选路线。

Mac 上可先验证无需签名的模拟器构建：

```sh
cd iOSClient
xcodebuild -project Lanpangzi.xcodeproj -scheme Lanpangzi \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

## 测试

### Windows/Mac 都可运行的逻辑验证

在包含安卓源码的仓库根目录运行：

```sh
python iOSClient/tools/generate_project.py
node iOSClient/Tests/bridge.test.cjs
python iOSClient/tools/check_project.py
```

生成器会覆盖生成的 `.pbxproj`、共享 Scheme 和 `game-start.js`，因此如已在 Xcode 中设置签名 Team/Bundle Identifier，重新生成后需要重新设置。不要在 `game-start.js` 中单独修改与安卓共用的入口逻辑。

### Xcode 测试

选择一个已安装的 iOS 17+ 模拟器，按 Product → Test。`CoreTests.swift` 覆盖 CDK 格式、危险地址拒绝、脚本完整性和六个持久化数据存储的同源 Cookie 隔离。**这些 Swift 测试尚未在当前 Windows 环境执行。**

先在 Scheme → Run → Arguments 添加 `-local-fixture`，运行本地六窗口测试。它不会登录游戏或保存真实 CDK，会自动打开六个不同颜色的本地页面，显示独立存储标记及计数，并通过真实桥接和安卓入口触发脚本注入。测试实际游戏时删除此参数。

### 真机验收（均待执行）

1. 本地六窗口同时出现，六个运行计数持续增加；横竖屏切换、放大/缩小、输入弹窗和点击位置正确。
2. 输入一个有效 CDK，验证所有实际平台跳转、自动选区/选角色、跨域游戏 frame、挂机面板及核心挂机动作。
3. 依次打开六个授权账号，核对角色不串号；退出 APP 后重新打开，验证登录数据和账号配置持久化。
4. 六开持续运行至少 30 分钟，放大某一窗口期间也检查其他五个窗口的游戏状态和任务进度；记录机型、系统、发热、内存回收和断线。
5. 验证重登、取消登录、失败重试、清除登录数据、删除账号、CDK 到期及脚本更新提示。
6. 记录切后台/锁屏后实际停止和恢复情况，不能用页面仍显示或计数显示正常代替游戏任务持续执行的证据。

## 已知边界

- iOS WebKit 对不可见/被覆盖页面、后台页面和多进程内存有系统限制，未使用私有 API 或网页“伪保活”补丁，六开稳定性必须以目标设备实测为准。
- 原加载器依赖安全上下文的 `crypto.subtle`、跨域请求及动态脚本执行；具体游戏平台的 HTTPS、CSP、CORS、iframe 或 iOS 浏览器限制可能要求后续适配，不能仅凭源码注入认为已经跑通。
- 允许 WebView 加载旧平台的 HTTP 内容；原生 CDK API 始终只使用固定的两个 HTTPS 节点，拒绝把 CDK 跟随重定向发送。没有放宽原生 API 的 ATS 或证书验证。
- 当前是开发测试工程，未完成 App Store 审核适配、正式图标与分发流程，也没有改动安卓发布、后台下载入口或线上更新接口。

## 文件

- `Sources/WorkspaceController.swift`：六窗口界面、账号操作、并发登录和窗口生命周期。
- `Sources/GameSession.swift`：独立 WebView、frame 脚本注入、桥接、弹窗和到期处理。
- `Sources/APIClient.swift`：原后台接口、禁止缓存和脚本校验。
- `Sources/Accounts.swift`：账号模型及 Keychain 存储。
- `Resources/bridge.js`：兼容原安卓 `CdkBridge` 的苹果桥接。
- `tools/generate_project.py`：确定性工程生成及安卓入口同步。
