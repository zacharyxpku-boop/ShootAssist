# 提审资产清单核查报告
生成时间：2026-04-19

核查范围：AppIcon 完整性 / StoreKit 隔离 / Info.plist 关键 key。
核查方式：纯静态文件检视，未执行 xcodebuild archive。

---

## 1. AppIcon [PASS]

**文件**：`ShootAssist/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`

**PNG 元数据**（`file` 命令输出）：
```
PNG image data, 1024 x 1024, 8-bit/color RGB, non-interlaced
```

核对项：

| 项目 | 要求 | 实测 | 结果 |
|---|---|---|---|
| 1024x1024 Marketing Icon | 必需 | 1024 x 1024 | PASS |
| 色彩模式 | RGB（非 RGBA） | 8-bit RGB | PASS |
| Alpha 通道 | App Store 拒透明 | 无 alpha | PASS |
| PNG 合法性 | 可被 `file` 识别 | `PNG image data` | PASS |
| 文件大小 | <1MB 推荐 | 972237 字节（≈949 KB） | PASS |

**Contents.json**（`ShootAssist/Assets.xcassets/AppIcon.appiconset/Contents.json`）：

```json
{
  "images" : [
    {
      "filename" : "AppIcon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

完全符合 iOS 17+ 单尺寸 AppIcon 策略（idiom=universal, platform=ios, size=1024x1024）。

---

## 2. StoreKit 隔离 [CAUTION]

**现状**：

- 文件位置：`ShootAssist/ShootAssist/ShootAssist.storekit`（位于 sources 根目录下）
- `project.yml` line 21-26：`resources:` 列表仅列 `Assets.xcassets` 与 `PrivacyInfo.xcprivacy`，**未**显式列 `.storekit` —— 注释也说明了为什么不放入 resources。

**风险点**（未 FAIL，但需验证）：

`project.yml` line 17-20 的 sources 配置：

```yaml
sources:
  - path: ShootAssist
    excludes:
      - "**/*.xcassets/*/Contents.json"
```

`excludes` **仅**排除 `Contents.json`，**未**排除 `**/*.storekit`。XcodeGen 遍历 `ShootAssist/` 目录时会把 `.storekit` 文件加入 target 的文件引用列表；Xcode 对 `.storekit` 的默认 build phase 分类是 resources（copy bundle resources），这意味着 Archive 构建很可能会把开发配置打进 .app bundle —— App Review 扫到直接拒审。

**两个解决方向（建议选其一）**：

1. 在 `project.yml` sources excludes 追加：
   ```yaml
   excludes:
     - "**/*.xcassets/*/Contents.json"
     - "**/*.storekit"
   ```
   最彻底，.storekit 完全不进 project，Scheme 里也无法引用 —— 如果不需要本地 StoreKit Testing 就选这个。

2. 保留进 project 但排除构建：把 `.storekit` 独立成 `buildPhase: none`（XcodeGen 语法）或用 `sources` 的 per-file 配置把它 type 标为 `file.storekit` 且不加入任何 phase。同时在生成后的 Scheme 里确认 `.storekit` 只绑在 **Run → Options → StoreKit Configuration**，不在 Archive / Test phase。

3. 把 `.storekit` 搬到 `ShootAssist/` sources 目录外（如项目根或 `tooling/`），Xcode Run Scheme 手动指定路径。

**`.xcodeproj` 不存在**：仓库靠 XcodeGen 按需生成 `.xcodeproj`，无法直接静态检查 Scheme。必须在生成工程后人工确认 Scheme → Archive → Post-actions/Options 不挂 storekit，且 .app bundle 内不含该文件。

**交付阁主：提审前 Archive 核查命令**

```bash
cd /c/Users/86136/Desktop/claude/ShootAssist
xcodegen generate  # 先生成 xcodeproj
xcodebuild -scheme ShootAssist -configuration Release archive \
  -archivePath build/ShootAssist.xcarchive
unzip -l build/ShootAssist.xcarchive/Products/Applications/ShootAssist.app | grep -i storekit
```

若最后一行输出**非空**，说明 .storekit 混进了 Release bundle，必须回头修 `project.yml` 的 excludes 或 Scheme 后再提审。

---

## 3. Info.plist [PASS]

**文件**：`ShootAssist/Info.plist`

6 项必查 key 齐全（行号基于 Info.plist）：

| Key | 行号 | 文案 | 评级 |
|---|---|---|---|
| NSCameraUsageDescription | 27-28 | 小白快门需要使用相机为您提供实时构图指导和姿势匹配功能 | OK — 说明了「为什么」+「价值」 |
| NSMicrophoneUsageDescription | 29-30 | 录制视频时需要使用麦克风收录现场声音 | OK |
| NSPhotoLibraryAddUsageDescription | 31-32 | 需要将您拍摄的照片和视频保存到相册 | OK |
| NSPhotoLibraryUsageDescription | 33-34 | 需要访问相册以导入参考照片或舞蹈视频 | OK |
| NSSpeechRecognitionUsageDescription | 37-38 | 识别您上传音乐中的歌词，自动生成对口型提示字幕 | OK |
| ITSAppUsesNonExemptEncryption | 23-24 | `<false/>` | OK — 免 ECCN 审查 |

**加分项**：

- Line 35-36 额外提供了 `NSPhotoLibraryLimitedAccessUsageDescription` —— iOS 14+ 的有限访问场景文案，非必填但体验好。

**潜在小问题**（非阻塞）：

- Line 30 `NSMicrophoneUsageDescription` 文案只说「收录现场声音」，严格按 App Review Guidelines 5.1.1 「explain how your app will use the data」来看还算合格，但可以更明确加一句「用于视频配音」。**非阻塞**。

- `CFBundleDevelopmentRegion` = `zh_CN`（line 5-6）配 `developmentLanguage: zh-Hans`（project.yml line 7）不完全一致（zh_CN 是 locale、zh-Hans 是 language tag），Xcode 通常兼容，但 App Store Connect 主语言建议统一为 `zh-Hans` 的 Simplified Chinese。**非阻塞**。

---

## 阻塞提审项

**严格阻塞（必须修才能提审）**：

- 无确认性阻塞项。

**高风险（提审前必须用 archive 命令实测一次）**：

- `project.yml` line 17-20：sources excludes 未排除 `**/*.storekit`。如果生成的 xcodeproj 把 `ShootAssist/ShootAssist/ShootAssist.storekit` 纳入 Copy Bundle Resources，Archive 产物会携带开发配置 → App Review 拒审。
  - **验证命令**：见第 2 节末尾 xcodebuild + unzip 组合。
  - **预防修**：`project.yml` excludes 追加 `"**/*.storekit"`（推荐）。

**软建议（不影响提审，但上架前顺手修）**：

- Info.plist line 30 NSMicrophoneUsageDescription 文案可加「用于视频配音」明确用途。
- `CFBundleDevelopmentRegion` 建议从 `zh_CN` 改 `zh-Hans` 保持与 project.yml developmentLanguage 一致。

---

## 汇总

- AppIcon：PASS
- StoreKit：CAUTION（需实测 archive 验证）
- Info.plist：PASS

提审可行性：**条件通过** —— 在 xcodebuild archive 后执行 `unzip -l ... | grep storekit` 输出为空，即可提审。
