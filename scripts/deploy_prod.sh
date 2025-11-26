#!/usr/bin/env bash
set -euo pipefail

# scripts/deploy_prod.sh
# Tauri Rust 後端生產環境部署腳本（遠程部署）。
# 功能概要：
#  - 通過 SSH 連接到遠程服務器
#  - 同步本地 src-tauri 代碼到遠程
#  - 在遠程編譯 Rust 項目
#  - 創建 systemd service 運行後端

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

# ========== 檢查 SSH 連接 ==========
echo -e "\n==> 檢查 SSH 連接..."
if ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$REMOTE_TARGET" "echo 'SSH connection successful'" 2>/dev/null; then
  echo "錯誤: 無法連接到 $REMOTE_TARGET"
  echo "請確保："
  echo "  1. SSH 密鑰已添加到遠程服務器: ssh-copy-id $REMOTE_TARGET"
  echo "  2. 或手動添加公鑰到遠程服務器的 ~/.ssh/authorized_keys"
  echo "  3. 遠程服務器的 SSH 服務正在運行"
  exit 1
fi
echo "SSH 連接成功！"

# ========== 同步本地代碼到遠程 ==========
echo -e "\n==> 同步本地 Tauri 代碼到遠程服務器..."

# 確保遠程目錄存在
ssh "$REMOTE_TARGET" "mkdir -p $TARGET_DIR"

# 使用 rsync 同步 src-tauri 目錄（排除構建產物）
echo "正在同步 src-tauri 目錄..."
rsync -avz --delete \
  --exclude 'target/' \
  --exclude 'gen/' \
  --exclude 'node_modules/' \
  --exclude '.git/' \
  --exclude '*.keystore' \
  --exclude 'keystore.properties' \
  "$REPO_ROOT/src-tauri/" \
  "$REMOTE_TARGET:$TARGET_DIR/src-tauri/"

echo "代碼同步完成！"

# ========== 在遠程服務器上執行部署 ==========
echo -e "\n==> 在遠程服務器上編譯和部署 Rust 後端..."

ssh "$REMOTE_TARGET" bash <<REMOTE_SCRIPT
set -euo pipefail

TARGET_DIR="$TARGET_DIR"
cd "\$TARGET_DIR/src-tauri"

echo -e "\n==> 1) 檢查 Rust 環境..."

# 安裝 Rust（如果不存在）
if ! command -v rustc >/dev/null 2>&1; then
  echo "Rust 未安裝，正在安裝..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "\$HOME/.cargo/env"
else
  echo "Rust 已安裝: \$(rustc --version)"
  source "\$HOME/.cargo/env" 2>/dev/null || true
fi

# 確保使用最新的 stable
rustup default stable
rustup update

echo -e "\n==> 2) 編譯 Rust 項目..."
cargo build --release

# 查找編譯好的二進制文件
BINARY_PATH="\$TARGET_DIR/src-tauri/target/release/hula"

if [ ! -f "\$BINARY_PATH" ]; then
  echo "錯誤: 編譯後的二進制文件不存在: \$BINARY_PATH"
  exit 1
fi

echo "編譯成功！二進制文件: \$BINARY_PATH"

echo -e "\n==> 3) 創建 systemd service..."

# 創建 systemd service 文件
sudo tee /etc/systemd/system/hula-backend.service >/dev/null <<EOF
[Unit]
Description=HuLa Tauri Backend
After=network.target

[Service]
Type=simple
User=\$USER
WorkingDirectory=\$TARGET_DIR/src-tauri
ExecStart=\$BINARY_PATH
Restart=on-failure
RestartSec=10
Environment=RUST_LOG=info

[Install]
WantedBy=multi-user.target
EOF

# 重新加載 systemd 並啟動服務
sudo systemctl daemon-reload
sudo systemctl enable hula-backend.service
sudo systemctl restart hula-backend.service

echo -e "\n==> 4) 檢查服務狀態..."
sudo systemctl status hula-backend.service --no-pager || true

echo -e "\n部署完成！"
REMOTE_SCRIPT

echo -e "\n==> 遠程部署完成！"
echo "你可以通過以下命令查看服務狀態："
echo "  ssh $REMOTE_TARGET"
echo "  sudo systemctl status hula-backend.service"
echo "  sudo journalctl -u hula-backend.service -f"
