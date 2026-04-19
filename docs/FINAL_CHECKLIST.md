# v1.0.0 上线最后一公里

截至 commit `a82fc6b` + tag `v1.0.0`，代码侧全部就绪。剩下的事只能你用手机和电脑操作。

## 步骤一 · GitHub Pages 开启（3 分钟）

- 打开 https://github.com/zacharyxpku-boop/ShootAssist/settings/pages
- Source → Deploy from a branch
- Branch → `main`，Folder → `/docs`
- Save
- 1-2 分钟后访问 https://zacharyxpku-boop.github.io/ShootAssist/privacy.html 应返回 200

## 步骤二 · 域名 shootassist.app 接到 Pages（可选但推荐）

如果已经买了 shootassist.app 域名：
- 域名注册商控制台加 CNAME：`shootassist.app` → `zacharyxpku-boop.github.io`
- GitHub Pages Settings → Custom domain 填 `shootassist.app` → Enforce HTTPS 勾
- DNS 传播 1-24 小时后 https://shootassist.app/privacy.html 生效

没买域名？跳过这步。需要把 `ShootAssist/Views/Paywall/PaywallView.swift` 里两条 URL
换成 `https://zacharyxpku-boop.github.io/ShootAssist/privacy.html` 和 `...terms.html`。
改完 push 会触发 `ios-dev` 出新 TestFlight build。

## 步骤三 · 等 Codemagic 把 v1.0.0 送上 TestFlight

- 打开 https://codemagic.io/apps → 选 ShootAssist → Builds
- `ios-release` workflow 应该在跑或已完成
- 绿钩 = IPA 已上传到 App Store Connect，约 10-30 分钟后 TestFlight 可见

如果红叉，点进去看最后一段日志。常见错误：
- 签名文件过期 → Codemagic 会自动拉新的，重跑一次即可
- `.storekit` 被打包 → 自检 step 会明确报哪个路径

## 步骤四 · iPhone 真机截图 5 张

在 iPhone 15/16 Pro Max（6.9" 或 6.7" 屏）上安装 TestFlight 的 v1.0.0，然后：

| # | 画面 | 操作 | 截图时机 |
|---|------|------|---------|
| 1 | 首页 | App 启动默认页 | 三大入口卡片清晰可见 |
| 2 | 拍同款 · 导入前 | 首页 → 拍同款 → 相机页 | 相机预览正常，顶部 tip 显示 |
| 3 | 拍同款 · 导入后 | 从相册选一张明显姿势的照片 | 剪影叠加出现在画面上 |
| 4 | 爆款姿势库 | 首页 → 爆款姿势 | 30 款网格展示 |
| 5 | Paywall | 触发超额或手动进设置 | 标题+价格+试用按钮 |

截完发送到电脑（邮件/AirDrop/云盘均可），原分辨率 1290×2796 或 1320×2868 PNG。

## 步骤五 · App Store Connect 填字

进 https://appstoreconnect.apple.com → 小白快门 → App Store 标签 → 1.0.0 版本

按 `docs/app_store_metadata.md` 的 16 段逐段粘贴：
- 名称 / 副标题 / 推广文本 / 描述 / 关键词（第 1-5 段）
- 截图上传区 → 拖 5 张进去（第 14 段）
- 支持 URL / 营销 URL / 隐私政策 URL（第 7 段）
- 年龄评级问卷（第 9 段，全选「无」出 4+）
- 提审说明（第 10 段，含 SA-REVIEW 邀请码免额度提示）
- Copyright（第 15 段）
- 欧盟贸易代表（第 16 段，必填）

内购商品（SubscriptionManager 里的 3 个 SKU）需要单独在 App Store Connect
「订阅」标签里创建并等 Apple 审核，建议跟 v1.0.0 一起提交。

## 步骤六 · 选 build 并提审

- 版本信息区 → 构建版本 → 选刚刚 Codemagic 传的 v1.0.0 build
- 右上角 **Submit for Review**
- 提审后 24-48 小时出结果

## 之后的版本（v1.0.1+）

我已经把 codemagic.yaml 里 `ios-release` 的 publishing 改成 `submit_to_app_store: true` +
`release_type: MANUAL`。流程变成：

1. 改代码 + 改 `docs/app_store_metadata.md` 里的 What's New 段
2. 在 App Store Connect 里新建 1.0.1 版本，填 What's New
3. `git tag v1.0.1 -m "..." && git push origin v1.0.1`
4. Codemagic 自动 build + 上传 + 提审
5. 审核通过后你手点 Release Now
