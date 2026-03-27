# 小白快门 - Xcode 项目配置指南

## 方式一：使用 XcodeGen 自动生成（推荐）

```bash
# 安装 xcodegen（只需一次）
brew install xcodegen

# 在 ShootAssist 目录下生成项目
cd ~/Desktop/ShootAssist
xcodegen generate

# 打开生成的项目
open ShootAssist.xcodeproj
```

## 方式二：手动创建 Xcode 项目

1. 打开 Xcode → File → New → Project
2. 选择 iOS → App
3. 配置：
   - Product Name: `ShootAssist`
   - Organization Identifier: `com.shootassist`
   - Interface: `SwiftUI`
   - Language: `Swift`
   - Minimum Deployments: `iOS 16.0`
4. 保存到桌面（替换或新建目录）
5. 删除 Xcode 自动生成的 `ContentView.swift`
6. 将 `ShootAssist/` 目录下所有子文件夹拖入 Xcode 项目导航器：
   - App/
   - Extensions/
   - Components/
   - Views/
   - ViewModels/
   - Models/
   - Utils/
   选择 "Create groups" 和 "Copy items if needed"
7. 用本项目的 `Info.plist` 替换 Xcode 生成的
8. 在 Build Settings 中确认：
   - `INFOPLIST_FILE` = `ShootAssist/Info.plist`
   - `GENERATE_INFOPLIST_FILE` = `NO`

## 真机运行

1. 用数据线连接 iPhone
2. Xcode 中选择你的真机设备
3. Signing & Capabilities → 选择你的 Apple ID 作为 Team
4. 按 ⌘R 编译运行

⚠️ 相机功能必须在真机上测试，模拟器无相机。
⚠️ 免费 Apple ID 安装的 App 有效期 7 天。
