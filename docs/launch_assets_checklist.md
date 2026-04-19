# 提审资产清单核查报告

最后更新：2026-04-19（第二轮核查）
核查方式：纯静态文件检视 + 源码扫描，未执行 xcodebuild archive。实测脚本见 `scripts/verify_no_storekit_in_release.sh`。

---

## 1. AppIcon [PASS]

**文件**：`ShootAssist/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`

PNG 元数据：
```
PNG image data, 1024 x 1024, 8-bit/color RGB, non-interlaced
```

| 项目 | 要求 | 实测 | 结果 |
|---|---|---|---|
| 1024x1024 Marketing Icon | 必需 | 1024 x 1024 | PASS |
| 色彩模式 | RGB（非 RGBA） | 8-bit RGB | PASS |
| Alpha 通道 | App Store 拒透明 | 无 alpha | PASS |
| PNG 合法性 | 可被 `file` 识别 | `PNG image data` | PASS |
| 文件大小 | <1MB 推荐 | 972237 字节（≈949 KB） | PASS |

Contents.json 符合 iOS 17+ 单尺寸 AppIcon 策略（idiom=universal, platform=ios, size=1024x1024）。

---

## 2. StoreKit 隔离 [PASS]

**project.yml 当前配置**（line 17-23）：

```yaml
sources:
  - path: ShootAssist
    excludes:
      - "**/*.xcassets/*/Contents.json"
      # StoreKit Testing 配置文件严禁进入 Release bundle（App Review 会扫到拒审）
      # 仅在 Xcode Scheme → Run → Options → StoreKit Configuration 里手动挂载
      - "**/*.storekit"
```

`**/*.storekit` 已加入 sources excludes，XcodeGen 不会把 `.storekit` 文件加入
Target 的文件引用列表，Release Archive 自然不会带它。`.storekit` 仅作为开发期
StoreKit Testing 资源，在 Xcode Scheme → Run → Options → StoreKit Configuration
里手动挂载使用。

**最终上传前仍需实测一次**（macOS）：

```bash
bash scripts/verify_no_storekit_in_release.sh
```

脚本会 xcodegen generate + archive，然后 find 扫 `.app` bundle 内所有
`.storekit` / `.storekitconfig` 文件。输出为空才能提审。

---

## 3. Info.plist [PASS]

**文件**：`ShootAssist/Info.plist`

5 项隐私字符串 + 1 项加密声明齐全：

| Key | 文案 | 评级 |
|---|---|---|
| CFBundleDevelopmentRegion | `zh-Hans` | PASS — 与 project.yml developmentLanguage 对齐 |
| NSCameraUsageDescription | 小白快门需要使用相机为您提供实时构图指导和姿势匹配功能 | PASS |
| NSMicrophoneUsageDescription | 录制视频时需要使用麦克风同步录入现场声音和配乐，方便后期剪辑 | PASS — 已加「配乐」明确用途 |
| NSPhotoLibraryAddUsageDescription | 需要将您拍摄的照片和视频保存到相册 | PASS |
| NSPhotoLibraryUsageDescription | 需要访问相册以导入参考照片或舞蹈视频 | PASS |
| NSPhotoLibraryLimitedAccessUsageDescription | 您已选择有限访问权限。如需导入更多参考照片，可在设置中调整为「完全访问」 | PASS — iOS 14+ 有限访问场景文案，加分 |
| ITSAppUsesNonExemptEncryption | `<false/>` | PASS — 免 ECCN 审查 |

**已删除**：`NSSpeechRecognitionUsageDescription` —— 歌词识别 / 对口型功能在 v1.0 已砍，对应 `LyricRecognitionService` / `LyricDatabase` / `LyricsView` 一并删除。不声明不需要的权限符合 App Review 5.1.1 最小权限原则。

**PrivacyInfo.xcprivacy** 文件存在（`ShootAssist/PrivacyInfo.xcprivacy`，iOS 17+ 必填）。

---

## 4. 死代码清理 [PASS]

2026-04-19 第二轮清理：

- **LyricRecognitionService.swift** —— 已删
- **Resources/LyricDatabase.swift** —— 已删
- **Views/Video/LyricsView.swift** —— 已删
- **VideoModeViewModel.swift** —— 对口型 / 歌词滚动 / 音频播放 / Vision 绑定代码全部删除，从 296 行缩到约 115 行
- **Info.plist NSSpeechRecognitionUsageDescription** —— 已删

清理原因：对口型功能在 v1.0 已在 UI 下线，源码残留既增加包体，又让 App Review 可能要求解释为什么声明了 Speech 权限却无入口调用。

验证：

```bash
rg 'Speech|SFSpeech|LyricRecognitionService|lyricDatabase|SongLyrics' ShootAssist/
# 空输出
```

---

## 汇总

- AppIcon：PASS
- StoreKit：PASS（静态 + 实测脚本就绪）
- Info.plist：PASS
- 死代码：PASS（第二轮清理完成）

**提审可行性：条件通过**

还需阁主在 macOS 上跑一次 `bash scripts/verify_no_storekit_in_release.sh`，输出为空就可以上传 Archive 到 App Store Connect 提审。
