# scripts/ — 上线前自检脚本

阁主在 macOS 上跑的一次性脚本集合。Windows 只能写脚本，不能跑。

## verify_no_storekit_in_release.sh

Archive Release 版并扫描 `.app` bundle 是否混入 `.storekit` 测试文件。

App Review 最常见的拒审理由之一：开发期 StoreKit Testing 配置被意外打进 Release bundle。

```bash
bash scripts/verify_no_storekit_in_release.sh
```

同时核验 Info.plist 4 条隐私字符串 + `PrivacyInfo.xcprivacy` 存在。

## deploy_docs.sh

把 `docs/privacy.html` `docs/terms.html` 发布到 GitHub Pages。App Store Connect
必填隐私政策 URL + 订阅用户协议 URL（Guideline 3.1.2）。

```bash
# 基础版（用 <user>.github.io/<repo> 的默认 URL）
bash scripts/deploy_docs.sh

# 挂自定义域（阁主已买 shootassist.app）
CUSTOM_DOMAIN=shootassist.app bash scripts/deploy_docs.sh
```

GitHub Settings → Pages → Source 选 `main` 分支 `/docs` 目录。
