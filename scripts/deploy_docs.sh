#!/usr/bin/env bash
# 把 docs/privacy.html 和 docs/terms.html 发布到 GitHub Pages
# App Store Connect 必填隐私政策 URL + 用户协议 URL
#
# 用法：
#   1. 在 GitHub 上新建 repo（或用已有 repo）
#   2. Settings → Pages → Source: "Deploy from a branch" → Branch: main, Folder: /docs
#   3. 运行 bash scripts/deploy_docs.sh
#   4. 等 1-2 分钟，访问 https://<user>.github.io/<repo>/privacy.html
#
# 自定义域（shootassist.app）：
#   1. 域名注册商加 CNAME: shootassist.app → <user>.github.io
#   2. 在 docs/ 下放 CNAME 文件，内容为 shootassist.app
#   3. GitHub Pages Settings 里填 Custom domain
#
# App Store Connect 填写：
#   隐私政策 URL: https://shootassist.app/privacy.html
#   支持 URL:     https://shootassist.app/
#   用户协议（APP 内订阅页）:     https://shootassist.app/terms.html

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

# 自检：docs 里必备文件
REQUIRED=(docs/privacy.html docs/terms.html)
for f in "${REQUIRED[@]}"; do
  if [ ! -f "$f" ]; then
    echo "✗ 缺 $f"
    exit 1
  fi
done

echo "▶ 本地文件检查通过"

# 如果要挂 shootassist.app，自动创建 CNAME
if [ "${CUSTOM_DOMAIN:-}" != "" ]; then
  echo "$CUSTOM_DOMAIN" > docs/CNAME
  echo "▶ 已写入 docs/CNAME: $CUSTOM_DOMAIN"
fi

# 检查 origin remote
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "✗ 本地仓库没有 origin remote"
  echo "  先执行: git remote add origin git@github.com:<user>/<repo>.git"
  exit 1
fi

echo "▶ 确认当前分支为 main"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$CURRENT_BRANCH" != "main" ]; then
  echo "✗ 当前分支不是 main（$CURRENT_BRANCH），GitHub Pages 只从 main/docs 发布"
  exit 1
fi

echo "▶ 推送 main 到 origin"
git push origin main

echo ""
echo "✓ 已推送。下一步："
echo "  1. GitHub Settings → Pages → Source: main /docs"
echo "  2. 等 1-2 分钟，访问："
echo "     https://<github_user>.github.io/<repo>/privacy.html"
echo "     https://<github_user>.github.io/<repo>/terms.html"
echo "  3. 把这两个 URL 填进 App Store Connect：应用隐私 + 订阅页"
