# 上线操作手册 — 你只需要做 3 件事

---

## 第一步：落地页上线（10分钟）

**目标：** shootassist.app 能打开

1. 打开 github.com → 新建私有仓库，名称 `shootassist-web`
2. 在命令行执行：
   ```
   cd C:\Users\86136\Desktop\claude\shootassist-web
   git remote add origin https://github.com/你的账号/shootassist-web.git
   git push -u origin master
   ```
3. 打开 vercel.com → 登录 → "Add New Project"
4. 选择 `shootassist-web` 仓库 → 直接点 Deploy（自动识别 Next.js）
5. 部署成功后 → Project Settings → Domains → 添加 shootassist.app
   - 去域名注册商把 DNS CNAME 指向 Vercel 提供的地址

---

## 第二步：iOS 云端编译上 TestFlight（30分钟）

### 2.1 获取 App Store Connect API Key
1. appstoreconnect.apple.com → 用户和访问 → 密钥 → 生成 API 密钥
   - 名称：Codemagic，权限：App Manager
2. 下载 .p8 私钥文件（只能下载一次，保存好）
3. 记录：Issuer ID（页面顶部）、Key ID（密钥列表）

### 2.2 创建 App
1. App Store Connect → 我的 App → + → 新建 App
2. 平台：iOS，名称：小白快门，Bundle ID：com.shootassist.app
3. 记录 URL 中的数字 App ID（如 6743XXXXXX）

### 2.3 填入 App ID
打开 codemagic.yaml 第 19 行，把 YOUR_APP_ID 替换为真实数字，然后：
   git add codemagic.yaml && git commit -m "set app id" && git push

### 2.4 配置 Codemagic
1. codemagic.io → GitHub 登录 → Add application → 选 ShootAssist 仓库
2. 选 codemagic.yaml 模式
3. Environment variables → 新建变量组 app_store_credentials，填入：
   APP_STORE_CONNECT_ISSUER_ID        = 2.1 的 Issuer ID
   APP_STORE_CONNECT_KEY_IDENTIFIER   = 2.1 的 Key ID
   APP_STORE_CONNECT_PRIVATE_KEY      = .p8 文件完整内容（含 BEGIN/END 行）
4. Start new build → Branch: main，Workflow: ios-dev
5. 等 15-20 分钟 → TestFlight 邮件通知 → 手机安装

---

## 第三步：发小红书（今天）

打开"小红书首发文案.md"，发篇一（种草向）。
配 2-3 张 before/after 对比截图。第3天发篇二，第7天发篇三。

---

完成标志：
[ ] shootassist.app 打开，分享有预览图
[ ] TestFlight 安装成功，拍同款流程走通
[ ] 小红书第一篇发出去
