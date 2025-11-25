#!/usr/bin/env bash
set -euo pipefail

# scripts/deploy_prod.sh
# 一鍵化生產環境部署腳本（半自動）。
# 功能概要：
#  - 檢查並安裝必要的系統套件（Debian/Ubuntu 假設）
#  - 建構前端 (pnpm build) 與 Tauri 應用 (若需要)
#  - 取得後端原始碼（從 .env 中的 VITE_SERVICE_URL 或手動提供），嘗試自動偵測語言/執行環境
#  - 為後端建立簡單 systemd service 或 Docker run 指令範例
#  - 列印後續手動調整建議

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "Repo root: $REPO_ROOT"

# ========== env loading ==========
if [ -f "$REPO_ROOT/.env.production" ]; then
  echo "Loading .env.production"
  # shellcheck disable=SC1091
  set -o allexport; source "$REPO_ROOT/.env.production"; set +o allexport
elif [ -f "$REPO_ROOT/.env" ]; then
  echo "Loading .env"
  set -o allexport; source "$REPO_ROOT/.env"; set +o allexport
else
  echo "No .env or .env.production found; proceed but backend repo URL may be unknown."
fi

# ========== helpers ===========
apt_install_if_missing() {
  PKG="$1"
  if ! dpkg -s "$PKG" >/dev/null 2>&1; then
    echo "Installing $PKG..."
    sudo apt-get update -y
    sudo apt-get install -y "$PKG"
  else
    echo "$PKG already installed"
  fi
}

# ========== 1. 環境準備（最低） ==========
echo "\n==> 1) 系統環境檢查（以 Debian/Ubuntu 為例）"
if [ "$(id -u)" -ne 0 ]; then
  echo "建議以非 root 帳號執行本腳本，腳本需要 sudo 權限來安裝套件。"
fi

# 檢查 git, curl, node, pnpm
command -v git >/dev/null 2>&1 || { echo "git not found: installing..."; apt_install_if_missing git; }
command -v curl >/dev/null 2>&1 || { echo "curl not found: installing..."; apt_install_if_missing curl; }

# Node & pnpm
if ! command -v node >/dev/null 2>&1; then
  echo "Node.js not found. Installing Node.js 22.x (apt setup)..."
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi

if ! command -v pnpm >/dev/null 2>&1; then
  echo "pnpm not found. Installing pnpm..."
  sudo npm install -g pnpm@latest
fi

# Rust (for Tauri backend if needed)
if ! command -v rustc >/dev/null 2>&1; then
  echo "rust not found. Installing rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
fi

# Docker optional
if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found. If you want to deploy backend as container, please install docker manually."
fi

# ========== 2. 建構前端與桌面 (若需要) ==========
echo "\n==> 2) 建構前端資產（pnpm build）"
if [ -f "$REPO_ROOT/package.json" ]; then
  echo "Installing node deps and building frontend..."
  pnpm install --frozen-lockfile || pnpm install
  pnpm build
else
  echo "No package.json found at repo root; skipping frontend build."
fi

# 若要同時建構 Tauri 桌面應用（可選）
if command -v pnpm >/dev/null 2>&1 && grep -q "tauri:build" package.json 2>/dev/null || true; then
  echo "\n==> Optional: build Tauri (desktop) app"
  read -p "Do you want to run 'pnpm exec tauri build' now? [y/N]: " yn
  yn="${yn:-N}"
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    pnpm exec tauri build
  else
    echo "Skipping Tauri build."
  fi
fi

# ========== 3. 後端準備 ==========
# 後端來源由 VITE_SERVICE_URL 決定（在 .env 裡），否則要求使用者輸入。
BACKEND_URL="${VITE_SERVICE_URL:-}" # from .env
if [ -z "$BACKEND_URL" ]; then
  echo "\n==> 3) 後端來源 (VITE_SERVICE_URL) 未在 .env 中設定。"
  read -p "請輸入後端 Git 倉庫 URL（或留空跳過）：" BACKEND_URL
fi

if [ -n "$BACKEND_URL" ]; then
  echo "後端 repo URL: $BACKEND_URL"
  TARGET_DIR="/opt/hula-backend"
  if [ ! -d "$TARGET_DIR" ]; then
    echo "Cloning backend to $TARGET_DIR (may require sudo)..."
    sudo mkdir -p "$TARGET_DIR"
    sudo chown "$USER":"$USER" "$TARGET_DIR"
    git clone "$BACKEND_URL" "$TARGET_DIR" || { echo "git clone failed"; exit 1; }
  else
    echo "$TARGET_DIR already exists. Pulling latest..."
    (cd "$TARGET_DIR" && git pull) || true
  fi

  echo "Detecting backend stack..."
  if [ -f "$TARGET_DIR/package.json" ]; then
    echo "Detected Node.js backend (package.json found)."
    # install & build
    cd "$TARGET_DIR"
    pnpm install || npm install
    if grep -q "build" package.json; then
      pnpm build || npm run build || true
    fi
    # decide run command
    if jq -r '.scripts.start // empty' package.json >/dev/null 2>&1; then
      RUN_CMD="pnpm start"
    else
      # try to find common entry
      if [ -f "dist/index.js" ]; then
        RUN_CMD="node dist/index.js"
      elif [ -f "build/index.js" ]; then
        RUN_CMD="node build/index.js"
      else
        RUN_CMD="pnpm start"
      fi
    fi

    echo "Preparing systemd service for Node backend..."
    SERVICE_FILE="/etc/systemd/system/hula-backend.service"
    sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=HuLa Backend
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$TARGET_DIR
Environment=NODE_ENV=production
ExecStart=/bin/bash -lc 'cd $TARGET_DIR && $RUN_CMD'
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    echo "You can enable and start service with: sudo systemctl enable --now hula-backend.service"

  elif [ -f "$TARGET_DIR/go.mod" ]; then
    echo "Detected Go backend (go.mod found)."
    cd "$TARGET_DIR"
    if command -v go >/dev/null 2>&1; then
      go build -o hula-backend ./...
    else
      echo "Go not installed; please install Go to build the backend."
    fi
    # systemd unit example
    SERVICE_FILE="/etc/systemd/system/hula-backend.service"
    sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=HuLa Backend (Go)
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$TARGET_DIR
ExecStart=$TARGET_DIR/hula-backend
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    echo "Enable and start: sudo systemctl enable --now hula-backend.service"

  elif [ -f "$TARGET_DIR/Dockerfile" ] || [ -f "$TARGET_DIR/docker-compose.yaml" ] || [ -f "$TARGET_DIR/docker-compose.yml" ]; then
    echo "Detected Docker-based backend. Building image and running container..."
    cd "$TARGET_DIR"
    if command -v docker >/dev/null 2>&1; then
      IMAGE_NAME="hula-backend:prod"
      sudo docker build -t "$IMAGE_NAME" .
      sudo docker run -d --name hula-backend -p 8080:8080 "$IMAGE_NAME"
      echo "Container started (map port 8080). Adjust port mapping as needed."
    else
      echo "Docker not installed. Please install docker or deploy with your orchestration tool."
    fi
  else
    echo "無法自動偵測後端框架。請手動進入 $TARGET_DIR 並依專案需求進行建構與部署。"
  fi
else
  echo "跳過後端部署步驟。"
fi

# ========== 4. 建議：反向代理與 TLS（nginx + certbot 範例） ==========
echo "\n==> 4) 建議的生產環境設定（手動）"
echo "- 建議使用 nginx 作為反向代理，並用 certbot 取得 TLS 憑證。"
echo "- 若需要，我可以幫你產生範例 nginx config 與 systemd 單元檔。"

# ========== 5. 結語 ==========
echo "\n部署腳本執行完畢。請根據輸出提示完成啟用與測試。"
echo "常見後續操作："
echo "  sudo systemctl enable --now hula-backend.service"
echo "  sudo journalctl -u hula-backend.service -f"
echo "  sudo ufw allow 80,443,8080/tcp (或按需開放 port)"

echo "若要我幫你自動化 nginx / certbot 或在 Docker Swarm / k8s 上部署，請告訴我你的偏好。"
