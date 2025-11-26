#!/usr/bin/env bash
set -euo pipefail

# scripts/deploy_docker.sh
# Docker Compose 部署腳本（遠程部署）。
# 功能概要：
#  - 先在本地測試 Docker 構建
#  - 通過 SSH 連接到遠程服務器
#  - 同步代碼和 Docker 配置到遠程
#  - 在遠程使用 Docker Compose 啟動服務

# ========== 遠程服務器配置 ==========
REMOTE_USER="${DEPLOY_USER:-mc}"
REMOTE_HOST="${DEPLOY_HOST:-165.154.205.8}"
REMOTE_TARGET="${REMOTE_USER}@${REMOTE_HOST}"
TARGET_DIR="/home/mc/data/project/koola-cloud/main/nf_chat"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "Repo root: $REPO_ROOT"
echo "Remote target: $REMOTE_TARGET"
echo "Remote directory: $TARGET_DIR"

# ========== 本地測試構建 ==========
echo -e "\n==> 1) 本地測試 Docker 構建..."
if ! docker build -t hula-backend:test -f src-tauri/Dockerfile . ; then
  echo "錯誤: 本地 Docker 構建失敗！"
  echo "請修復構建問題後再部署。"
  exit 1
fi
echo "✓ 本地構建成功！"

# ========== 檢查 SSH 連接 ==========
echo -e "\n==> 2) 檢查 SSH 連接..."
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$REMOTE_TARGET" "echo 'SSH connection successful'" 2>/dev/null; then
  echo "錯誤: 無法連接到 $REMOTE_TARGET"
  echo "請確保："
  echo "  1. SSH 密鑰已添加到遠程服務器: ssh-copy-id $REMOTE_TARGET"
  echo "  2. 或手動添加公鑰到遠程服務器的 ~/.ssh/authorized_keys"
  echo "  3. 遠程服務器的 SSH 服務正在運行"
  exit 1
fi
echo "✓ SSH 連接成功！"

# ========== 同步代碼到遠程 ==========
echo -e "\n==> 3) 同步項目代碼到遠程服務器..."

# 確保遠程目錄存在
ssh "$REMOTE_TARGET" "mkdir -p $TARGET_DIR"

# 使用 rsync 同步項目（排除構建產物和敏感文件）
echo "正在同步項目文件..."
rsync -avz --delete \
  --exclude 'target/' \
  --exclude 'gen/' \
  --exclude 'node_modules/' \
  --exclude '.git/' \
  --exclude '*.keystore' \
  --exclude 'keystore.properties' \
  --exclude 'logs/' \
  --exclude 'data/' \
  --exclude 'dist/' \
  --exclude '.env.local' \
  "$REPO_ROOT/" \
  "$REMOTE_TARGET:$TARGET_DIR/"

echo "✓ 代碼同步完成！"

# ========== 在遠程執行 Docker Compose 部署 ==========
echo -e "\n==> 4) 在遠程服務器上啟動 Docker Compose..."

ssh "$REMOTE_TARGET" bash <<REMOTE_SCRIPT
set -euo pipefail

cd "$TARGET_DIR"

echo "檢查 Docker 和 Docker Compose..."
if ! command -v docker >/dev/null 2>&1; then
  echo "錯誤: Docker 未安裝！"
  echo "請先安裝 Docker: https://docs.docker.com/engine/install/"
  exit 1
fi

if ! command -v docker-compose >/dev/null 2>&1 && ! docker compose version >/dev/null 2>&1; then
  echo "錯誤: Docker Compose 未安裝！"
  echo "請先安裝 Docker Compose: https://docs.docker.com/compose/install/"
  exit 1
fi

echo "✓ Docker 環境就緒"

# 停止舊容器（如果存在）
echo "停止舊容器..."
docker-compose -f docker-compose.backend.yml down || docker compose -f docker-compose.backend.yml down || true

# 構建並啟動服務
echo "構建並啟動服務..."
if command -v docker-compose >/dev/null 2>&1; then
  docker-compose -f docker-compose.backend.yml up -d --build
else
  docker compose -f docker-compose.backend.yml up -d --build
fi

# 等待服務啟動
echo "等待服務啟動..."
sleep 5

# 檢查容器狀態
echo -e "\n容器狀態："
if command -v docker-compose >/dev/null 2>&1; then
  docker-compose -f docker-compose.backend.yml ps
else
  docker compose -f docker-compose.backend.yml ps
fi

# 查看日誌
echo -e "\n最近日誌："
if command -v docker-compose >/dev/null 2>&1; then
  docker-compose -f docker-compose.backend.yml logs --tail=50 hula-backend
else
  docker compose -f docker-compose.backend.yml logs --tail=50 hula-backend
fi

echo -e "\n✓ 部署完成！"
REMOTE_SCRIPT

echo -e "\n==> 遠程部署完成！"
echo ""
echo "你可以通過以下命令管理服務："
echo "  ssh $REMOTE_TARGET"
echo "  cd $TARGET_DIR"
echo ""
echo "查看日誌："
echo "  docker-compose -f docker-compose.backend.yml logs -f hula-backend"
echo ""
echo "停止服務："
echo "  docker-compose -f docker-compose.backend.yml down"
echo ""
echo "重啟服務："
echo "  docker-compose -f docker-compose.backend.yml restart hula-backend"
