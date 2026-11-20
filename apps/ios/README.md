# 知行 iOS

独立的 SwiftUI + MapKit iOS App。地图顶部可在「知 · 视频」与「行 · 足迹」之间切换：前者只显示有视频的地点，后者只显示自己的足迹。可在行地图里搜索地点，记录到访日期和一句话；新足迹默认仅自己可见。

## 运行

需要 macOS、完整 Xcode（不是仅 Command Line Tools）和 XcodeGen：

```sh
brew install xcodegen
xcodegen generate
open Zhixing.xcodeproj
```

在 Xcode 中选择 iPhone Simulator 后运行。默认请求 `http://localhost:8787`，模拟器可访问本机运行的 API。

真机或发布构建时，将 `APP_API_BASE` 设置为可从设备访问的 HTTPS API 地址。例如：

```sh
xcodebuild -project Zhixing.xcodeproj -scheme Zhixing \
  -destination 'generic/platform=iOS' APP_API_BASE=https://你的-api-域名 build
```

不要把真实服务地址、证书或签名材料提交到仓库。当前 API 仍由已有服务提供；多端 API 代码迁入此仓库时再建立 `apps/api`。

## 接口

- `GET /places/pins`：地图地点与坐标。
- `GET /places/:id`：地点简介、层级路径与关联外链。
- `GET /me/footprints`、`POST /footprints`：读取和记录个人足迹。

外链平台包括小红书、B 站、抖音、微博和其他网页。App 只展示 HTTPS 链接；平台 App 已安装时由 iOS 决定打开方式，否则由系统网页浏览器打开。
