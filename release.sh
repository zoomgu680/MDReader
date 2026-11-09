#!/usr/bin/env bash
# ============================================================
# MDReader - Release 发布脚本 (macOS / Linux bash)
# 用途：更新版本号 -> 同步 dist -> 构建安装包 -> 提交+打 tag -> 创建 GitHub Release
# 顺序说明：构建成功后才提交并打 tag，避免构建失败时留下无效远程 tag
# 用法：
#   ./release.sh 0.1.1                        # 发布 0.1.1
#   ./release.sh 0.1.1 --skip-build           # 跳过构建
#   ./release.sh 0.1.1 -n "修复了xxx"          # 自定义 release notes
#   ./release.sh 0.1.1 --draft                # 创建为草稿
# 注意：Windows WebView2 安装包需在 Windows 上构建，
#       macOS 上此脚本仅构建 .dmg/.app 并创建 Release。
# ============================================================
set -e

VERSION=""
SKIP_BUILD=false
NOTES=""
DRAFT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build) SKIP_BUILD=true; shift ;;
        -n|--notes)   NOTES="$2"; shift 2 ;;
        --draft)      DRAFT=true; shift ;;
        -*) echo "未知参数: $1"; exit 1 ;;
        *)  VERSION="$1"; shift ;;
    esac
done

if [[ -z "$VERSION" ]]; then
    echo "用法: $0 <X.Y.Z> [--skip-build] [-n notes] [--draft]"
    exit 1
fi

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo -e "\033[31m[ERROR] 版本号格式错误，应为 X.Y.Z\033[0m"
    exit 1
fi

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

TAG="v$VERSION"
PRODUCT="MDReader"

log_info()  { echo -e "\033[36m[INFO]  $1\033[0m"; }
log_ok()    { echo -e "\033[32m[OK]    $1\033[0m"; }
log_warn()  { echo -e "\033[33m[WARN]  $1\033[0m"; }
log_err()   { echo -e "\033[31m[ERROR] $1\033[0m"; }
step()      { echo -e "\n\033[35m=== $1 ===\033[0m"; }

command -v git >/dev/null || { log_err "未找到 git"; exit 1; }

# 注意：gh CLI 的可用性/认证检查放在最后一步（真正用到时），
# 这样即使 gh 未就绪，版本号更新/构建/提交/打 tag/推送也已完成

STATUS=$(git status --porcelain)
if [[ -n "$STATUS" ]]; then
    log_warn "工作区有未提交变更，建议先用 ./update.sh 提交"
    read -r -p "是否继续？(y/N) " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0
fi

# 1. 更新版本号（tauri.conf.json / Cargo.toml / index.html）
step "1/6 更新版本号到 $VERSION"
TAURI_CONF="$ROOT/src-tauri/tauri.conf.json"
CARGO_TOML="$ROOT/src-tauri/Cargo.toml"
INDEX_HTML="$ROOT/index.html"

# BSD sed 与 GNU sed 均支持 -i.bak 写法
sed -i.bak -E 's/"version": *"[0-9]+\.[0-9]+\.[0-9]+"/"version": "'"$VERSION"'"/' "$TAURI_CONF"
rm -f "$TAURI_CONF.bak"
if grep -q "\"$VERSION\"" "$TAURI_CONF"; then
    log_ok "tauri.conf.json 版本已更新为 $VERSION"
else
    log_err "tauri.conf.json 版本号更新失败"
    exit 1
fi

sed -i.bak -E 's/^version *= *"[0-9]+\.[0-9]+\.[0-9]+"/version = "'"$VERSION"'"/' "$CARGO_TOML"
rm -f "$CARGO_TOML.bak"
if grep -q "^version = \"$VERSION\"" "$CARGO_TOML"; then
    log_ok "Cargo.toml 版本已更新为 $VERSION"
else
    log_err "Cargo.toml 版本号更新失败"
    exit 1
fi

# index.html（关于弹窗中的版本号显示）
sed -i.bak -E 's/版本 *[0-9]+\.[0-9]+\.[0-9]+/版本 '"$VERSION"'/g' "$INDEX_HTML"
rm -f "$INDEX_HTML.bak"
if grep -q "版本 $VERSION" "$INDEX_HTML"; then
    log_ok "index.html 关于弹窗版本已更新为 $VERSION"
else
    log_warn "index.html 中未找到版本号文本，可能已是 $VERSION"
fi

# 2. 同步 dist
step "2/6 同步 dist"
mkdir -p "$ROOT/dist/resources"
cp "$ROOT/index.html" "$ROOT/dist/index.html"
cp -R "$ROOT/resources/"* "$ROOT/dist/resources/"
log_ok "dist 同步完成"

# 3. 构建安装包
step "3/6 构建安装包"
BUNDLE_DIR="$ROOT/src-tauri/target/release/bundle"
ASSETS=()

if [[ "$SKIP_BUILD" == "true" ]]; then
    log_warn "跳过构建 (--skip-build)"
else
    cd "$ROOT/src-tauri"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        log_info "构建 macOS 包 (.app + .dmg)..."
        cargo tauri build --bundles app,dmg
        DMG=$(ls "$BUNDLE_DIR/dmg/"*.dmg 2>/dev/null | head -1)
        [[ -n "$DMG" ]] && ASSETS+=("$DMG") && log_ok "macOS 包: $DMG"
    else
        log_info "构建 Linux 包 (.AppImage)..."
        cargo tauri build --bundles appimage
        APPIMG=$(ls "$BUNDLE_DIR/appimage/"*.AppImage 2>/dev/null | head -1)
        [[ -n "$APPIMG" ]] && ASSETS+=("$APPIMG") && log_ok "Linux 包: $APPIMG"
    fi
    cd "$ROOT"

    if [[ ${#ASSETS[@]} -eq 0 ]]; then
        log_err "未找到构建产物"
        exit 1
    fi
fi

# 4. 提交版本变更并创建 tag（构建成功后才执行）
step "4/6 提交版本变更并创建 tag"
# 构建会把 Cargo.lock 中的版本同步为 $VERSION，此处一并纳入提交
git add --all
if ! git commit -m "Bump version to $VERSION" >/dev/null; then
    log_err "git commit 失败"
    exit 1
fi
log_ok "版本变更已提交: $(git log --oneline -1)"

if git tag -l "$TAG" | grep -q .; then
    log_warn "tag $TAG 已存在"
    read -r -p "删除后重建？(y/N) " confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && exit 0
    git tag -d "$TAG" >/dev/null
    git push origin ":refs/tags/$TAG" 2>/dev/null || true
fi

git tag -a "$TAG" -m "$PRODUCT $TAG"
log_ok "本地 tag $TAG 已创建"

git push origin main 2>/dev/null || true
git push origin "$TAG" 2>/dev/null || true

# push 可能因环境限制返回非零但实际成功，用远程状态校验代替退出码判断
LOCAL_HEAD=$(git rev-parse HEAD)
REMOTE_MAIN=$(git ls-remote origin refs/heads/main | awk '{print $1}')
REMOTE_TAG=$(git ls-remote origin "refs/tags/$TAG" | awk '{print $1}')
if [[ "$REMOTE_MAIN" != "$LOCAL_HEAD" ]]; then
    log_err "main 推送失败（远程为 $REMOTE_MAIN，本地为 $LOCAL_HEAD）"
    exit 1
fi
if [[ -z "$REMOTE_TAG" ]]; then
    log_err "tag $TAG 推送失败"
    exit 1
fi
log_ok "main 与 tag $TAG 已推送到远程"

# 5. Release notes
step "5/6 生成 Release Notes"
if [[ -z "$NOTES" ]]; then
    NOTES=$(mktemp)
    YEAR=$(date +%Y)
    cat > "$NOTES" <<EOF
# $PRODUCT $TAG

MDReader Markdown 阅读器新版本发布。

## 安装包

| 文件 | 说明 |
|---|---|
| 见下方 Assets | 对应平台安装包 |

## 许可证

MIT / Apache-2.0 双协议

版权所有 (C) $YEAR 中国邮政集团有限公司浙江省信息技术中心
(China Post Group Co., Ltd. Zhejiang IT Center)
EOF
    log_ok "已生成默认 Release Notes"
fi

# 6. 创建 Release
step "6/6 创建 GitHub Release"
if ! command -v gh >/dev/null; then
    log_err "未找到 gh CLI，请安装后执行: gh auth login"
    exit 1
fi
if ! gh auth status &>/dev/null; then
    log_err "gh 未认证，请先执行: gh auth login"
    log_warn "认证后可用以下命令手动完成发布（安装包与 tag 已就绪）："
    echo "        gh release create $TAG ${ASSETS[*]} --title \"$PRODUCT $TAG\" --notes-file \"$NOTES\" --latest"
    exit 1
fi

RELEASE_ARGS=("release" "create" "$TAG" "--title" "$PRODUCT $TAG" "--notes-file" "$NOTES")
[[ "$DRAFT" == "true" ]] && RELEASE_ARGS+=("--draft") || RELEASE_ARGS+=("--latest")
for f in "${ASSETS[@]}"; do RELEASE_ARGS+=("$f"); done

log_info "执行: gh ${RELEASE_ARGS[*]}"
gh "${RELEASE_ARGS[@]}" || { log_err "创建 Release 失败"; exit 1; }
log_ok "Release $TAG 发布成功！"

[[ -f "$NOTES" ]] && rm -f "$NOTES"

echo -e "\n\033[32m========================================\033[0m"
echo -e "\033[32m  发布完成: $PRODUCT $TAG\033[0m"
echo -e "\033[32m  Release: https://github.com/zoomgu680/MDReader/releases/tag/$TAG\033[0m"
echo -e "\033[32m========================================\n\033[0m"
