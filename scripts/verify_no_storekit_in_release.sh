#!/usr/bin/env bash
# 验证 Release .ipa / .xcarchive 中不包含 .storekit 配置文件
# App Review 扫到开发配置文件会拒审（Guideline 2.3.1 accurate metadata / 2.5.1 testing artifacts）
#
# 用法（macOS）：
#   bash scripts/verify_no_storekit_in_release.sh
#
# 前置：
#   - brew install xcodegen（或 mint install yonaskolb/xcodegen）
#   - 已配置 Apple Developer Team（project.yml 里 DEVELOPMENT_TEAM）

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "▶ 1. 重新生成 Xcode 工程"
xcodegen generate

echo "▶ 2. Archive Release 版"
ARCHIVE_PATH="$REPO_ROOT/build/ShootAssist.xcarchive"
rm -rf "$ARCHIVE_PATH"
xcodebuild -scheme ShootAssist \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  CODE_SIGNING_ALLOWED=NO

APP_BUNDLE="$ARCHIVE_PATH/Products/Applications/ShootAssist.app"

if [ ! -d "$APP_BUNDLE" ]; then
  echo "✗ 没有找到 $APP_BUNDLE"
  exit 1
fi

echo "▶ 3. 扫描 .app bundle 内的 .storekit 文件"
STOREKIT_HITS=$(find "$APP_BUNDLE" -iname "*.storekit" -o -iname "*.storekitconfig" 2>/dev/null || true)

if [ -n "$STOREKIT_HITS" ]; then
  echo ""
  echo "✗ 危险：Release bundle 内混入了 StoreKit 测试配置："
  echo "$STOREKIT_HITS"
  echo ""
  echo "修复：project.yml 的 sources.excludes 需包含 \"**/*.storekit\""
  exit 1
fi

echo "▶ 4. 核对 Info.plist 必备隐私字符串"
INFO_PLIST="$APP_BUNDLE/Info.plist"
REQUIRED_KEYS=(
  NSCameraUsageDescription
  NSMicrophoneUsageDescription
  NSPhotoLibraryAddUsageDescription
)
# 注意：不再要求 NSPhotoLibraryUsageDescription — 我们只用 PHPicker + addOnly，
# 声明整读权限会被 App Review 质疑「为什么要全读」。
MISSING=()
for key in "${REQUIRED_KEYS[@]}"; do
  if ! /usr/libexec/PlistBuddy -c "Print :$key" "$INFO_PLIST" >/dev/null 2>&1; then
    MISSING+=("$key")
  fi
done

if [ ${#MISSING[@]} -gt 0 ]; then
  echo "✗ Info.plist 缺隐私字符串："
  printf '   - %s\n' "${MISSING[@]}"
  exit 1
fi

echo "▶ 5. 核对 PrivacyInfo.xcprivacy 存在"
if [ ! -f "$APP_BUNDLE/PrivacyInfo.xcprivacy" ]; then
  echo "✗ 缺 PrivacyInfo.xcprivacy（iOS 17+ 必须）"
  exit 1
fi

echo ""
echo "✓ Release bundle 自检通过："
echo "   - 无 .storekit 测试文件"
echo "   - 3 条隐私字符串齐全（Camera / Microphone / PhotoLibraryAdd）"
echo "   - PrivacyInfo.xcprivacy 存在"
echo ""
echo "下一步：xcodebuild -exportArchive 生成 .ipa 后再跑一次本脚本对 .ipa 解压后的 .app 扫一遍。"
