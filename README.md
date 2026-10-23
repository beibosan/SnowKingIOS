# 雪花之王 iOS

这是一个可在 Xcode 中打开的 iOS 工程骨架，包含：

- Swift/UIKit 账号管理、横向/纵向多开和设置页
- WKWebView 游戏容器
- `GameAssets` 中的 Cocos H5 资源
- 雪花主题图标与浅色 UI
- iOS 15.0，arm64，Bundle ID `com.snowking.ios`

## 在 macOS 上构建

1. 用 Xcode 打开 `SnowKingIOS.xcodeproj`。
2. 在 Target > Signing & Capabilities 中选择你的 Apple Developer Team。
3. 修改 Bundle Identifier，确保它在开发者账号中唯一。
4. 选择真机或 Generic iOS Device，执行 Archive。
5. 通过 Organizer 导出 IPA。

Windows 环境没有 Xcode 和 Apple 签名工具，因此这里只能生成工程，不能在本机直接导出可安装 IPA。

## 资源说明

`GameAssets` 来自用户提供的 `FFF` 目录。资源内的登录脚本、远程 CDN 和账号协议只应在获得授权的测试环境使用；本工程不包含 Apple 签名证书、Provisioning Profile 或第三方账号凭据。

## 当前版本

版本：v1.2.3，Build 3。GitHub Actions 会在 macOS 上构建未签名 IPA。
