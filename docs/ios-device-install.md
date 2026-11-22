# iOS 真机安装与 API 配置

本文用于把知行安装到 iPhone 并确认 App 能连接知行服务。安装成功只说明签名和传输正常；如果 API 地址错了或不可达，地图、登录、注册仍会报网络错误。每次真机安装都按以下顺序检查，不根据记忆猜地址。

## 安装前检查

### 1. 确认 Xcode 签名

1. 用 Xcode 打开 `apps/ios/Zhixing.xcodeproj`，选择 `Zhixing` scheme 和已连接的 iPhone。
2. 在 Target → Signing & Capabilities 中启用 Automatically manage signing，选择已登录且有开发团队权限的 Apple Developer Team。
3. 确认 Bundle Identifier 是 `app.zhixing.ios`，Xcode 能为所选 Team 和这台设备取得有效的 provisioning profile。开发 profile 必须包含当前 iPhone 的 UDID。
4. 如 Xcode 报“找不到开发团队/描述文件/设备不在 profile 中”，先修复 Apple ID、Team、设备注册或 profile，再安装。证书存在不代表该 App 和设备已有可用描述文件。

命令行构建可显式指定团队。不要照抄占位值；Team ID 必须和已配置的开发账号相符：

```sh
xcodebuild \
  -project apps/ios/Zhixing.xcodeproj \
  -scheme Zhixing \
  -configuration Debug \
  -destination 'id=<当前 iPhone 的 UDID>' \
  -derivedDataPath /tmp/zhixing-device-build \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM='<Apple Developer Team ID>' \
  APP_API_BASE='<已验证的手机可访问 API HTTPS 地址>' \
  build
```

### 2. 确认 API 地址

`apps/ios/project.yml` 的默认 `APP_API_BASE` 是 `http://localhost:8787`，仅供 iOS Simulator 访问 Mac 上的本地开发 API。真机上的 `localhost` 指 iPhone 自己，不是开发 Mac，也不是生产服务器。不可把这个默认值用于 iPhone 真机。

每次真机或发布构建前：

1. 从当前部署配置或服务负责人处确认 API 的正式 HTTPS 根地址。不要凭旧对话、旧 IP、旧域名、管理后台地址或 S3 地址猜测；客户端 API 地址必须指向提供 `/health`、`/places/pins`、`/auth/email/send` 等 API 路由的服务。
2. 从开发 Mac 的网络环境检查该地址：

   ```sh
   curl -fsS --max-time 10 '<API HTTPS 地址>/health'
   ```

   预期返回健康 JSON（例如 `{"ok":true}`）。TLS 握手、证书校验或连接失败时，先修复地址、证书或网络入口，不要继续把它当作可用地址打包。
3. 确认 iPhone 当前网络也能访问这个 HTTPS 地址。若手机使用蜂窝网络、VPN、代理或不同 Wi-Fi，Mac 成功不能证明手机也能访问；可在 iPhone Safari 打开 `/health` 验证 TLS 和网络路径。
4. 构建时显式传入已确认地址：`APP_API_BASE=https://...`。成功构建后，检查产物内的配置确实不是 localhost：

   ```sh
   /usr/libexec/PlistBuddy \
     -c 'Print :APIBase' \
     /tmp/zhixing-device-build/Build/Products/Debug-iphoneos/知行.app/Info.plist
   ```

   输出应与已验证的 API 根地址一致。检查通过后再安装，避免把模拟器配置误装到手机。

若目前没有确认可用的真机 API 地址，先停止在“待配置 API”状态：可以构建供本地检查，但地图、登录、注册等网络功能不会在手机上正常工作。不要自行把 `localhost` 换成未经核实的 IP；HTTPS 证书也必须对该主机名或 IP 有效。

### 3. 确认安装对象

确认 iPhone 已连接、已配对，并已开启 Developer Mode：

```sh
xcrun devicectl list devices
```

安装时使用刚才成功构建的 `.app` 路径和对应设备 UDID：

```sh
xcrun devicectl device install app \
  --device '<当前 iPhone 的 UDID>' \
  /tmp/zhixing-device-build/Build/Products/Debug-iphoneos/知行.app
```

确认安装成功后启动：

```sh
xcrun devicectl device process launch \
  --device '<当前 iPhone 的 UDID>' \
  app.zhixing.ios
```

## 从登录/注册页开始

登录令牌保存在 iOS Keychain 中。卸载 App 再安装**不保证**清除 Keychain 项；不能把卸载重装当成重置登录态的方法。

当前代码支持仅 Debug 生效的启动参数 `--reset-session`。在 Xcode 的 Zhixing scheme → Run → Arguments Passed On Launch 中添加它，启动一次后会删除本地令牌，再移除该参数。Release 构建会忽略此参数。此操作只重置本机登录令牌，不会删除服务器账号，也不会修复 API 地址或签名问题。不要在真机上因登录页未出现而反复卸载，先判断是 Keychain 中仍有会话，还是 `/me` 网络请求失败。

## 安装后验证

1. 登录/注册页打开后，验证邮箱验证码服务可用；若提示连接失败，先检查构建产物中的 `APIBase`、手机到 `/health` 的访问和 TLS 证书，不要先清账号或重置服务器。
2. 登录后确认地图地点加载。服务器访问日志中应能看到来自 App 的 `/me` 与 `/places/pins` 请求，并返回成功状态。
3. 若需返回登录页，使用 Debug 的 `--reset-session` 参数；仅覆盖安装不会清除 Keychain 登录状态。
4. 若构建签名失败，不要卸载手机上现有版本。修复签名并成功生成新 `.app` 后，再执行安装命令。

## 故障快速判断

| 表现 | 先检查 |
| --- | --- |
| Xcode 找不到 Team 或 provisioning profile | Apple ID 登录状态、Team 权限、Bundle ID、设备 UDID 是否在开发 profile 中 |
| App 打开但一直加载或提示 TLS error | 产物 `APIBase` 是否不是 localhost、域名/IP 是否当前有效、HTTPS 证书是否匹配且有效、手机网络是否能到达服务 |
| 手机还停留在已登录状态 | Keychain 会跨卸载保留；用 Debug 的 `--reset-session` 启动一次 |
| Safari `/health` 正常但 App 请求失败 | 确认安装的 `.app` 使用同一 API 地址，并查看 App 请求路径和服务器访问日志 |
| Mac 上 `/health` 正常但手机失败 | 手机所用 Wi-Fi/蜂窝网络、VPN/代理、DNS 和防火墙入口可能不同；以手机网络实测为准 |
