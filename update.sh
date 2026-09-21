#!/usr/bin/env bash
# ============================================================
# MDReader - 源码更新脚本 (macOS / Linux bash)
# 用途：同步 dist -> 提交变更 -> 推送到 GitHub
# 用法：
#   ./update.sh                          # 自动生成提交信息
#   ./update.sh -m "修复xxx"             # 指定提交信息
#   ./update.sh --no-push               # 只提交不推送
#   ./update.sh --no-sync               # 跳过 dist 同步
# ============================================================
set -e

MESSAGE=""
NO_PUSH=false
NO_SYNC=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -m|--message) MESSAGE="$2"; shift 2 ;;
        --no-push)   NO_PUSH=true; shift ;;
        --no-sync)   NO_SYNC=true; shift ;;
        *) echo "未知参数: $1"; exit 1 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

log_info()  { echo -e "\033[36m[INFO]  $1\033[0m"; }
log_ok()    { echo -e "\033[32m[OK]    $1\033[0m"; }
log_warn()  { echo -e "\033[33m[WARN]  $1\033[0m"; }
log_err()   { echo -e "\033[31m[ERROR] $1\033[0m"; }

if ! command -v git &>/dev/null; then
    log_err "未找到 git"
    exit 1
fi

# 同步 dist
if [[ "$NO_SYNC" != "true" ]]; then
    log_info "同步 dist 目录..."
    mkdir -p "$ROOT/dist/resources"
    cp "$ROOT/index.html" "$ROOT/dist/index.html"
    cp -R "$ROOT/resources/"* "$ROOT/dist/resources/"
    log_ok "dist 同步完成"
else
    log_warn "跳过 dist 同步"
fi

# 检查状态
STATUS=$(git status --porcelain)
if [[ -z "$STATUS" ]]; then
    log_ok "工作区干净，无变更"
    exit 0
fi

CHANGED=$(echo "$STATUS" | wc -l | tr -d ' ')
log_info "检测到 $CHANGED 个变更文件："
echo "$STATUS" | sed 's/^/        /'

# 暂存
log_info "暂存所有变更..."
git add --all

# 提交信息
if [[ -z "$MESSAGE" ]]; then
    FILES=$(echo "$STATUS" | grep -E '^\s*[AM]' | sed -E 's/^\s*[AM]\s+//' | tr '\n' ',' | sed 's/,$//')
    if [[ ${#FILES} -gt 80 ]]; then FILES="${FILES:0:77}..."; fi
    MESSAGE="更新: $FILES"
fi
log_info "提交信息: $MESSAGE"

git commit -m "$MESSAGE" || { log_err "git commit 失败"; exit 1; }
log_ok "提交成功: $(git log --oneline -1)"

if [[ "$NO_PUSH" == "true" ]]; then
    log_warn "跳过推送 (--no-push)"
    exit 0
fi

log_info "推送到 origin/main..."
git push origin main || { log_err "git push 失败"; exit 1; }
log_ok "推送成功"
