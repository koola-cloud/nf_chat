#!/usr/bin/env bash
set -euo pipefail

# scripts/android_build_test.sh
# 一鍵初始化 Rust、Android SDK/NDK、Node 依賴、Tauri Android 環境、產生測試 keystore，並執行 Android 构建。

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

echo "Repository root: $REPO_ROOT"

# ============================================
# 1. 檢查與安裝 Rust toolchain
# ============================================
echo "1) 檢查 Rust toolchain..."
if ! command -v rustc >/dev/null 2>&1; then
  echo "  -> Rust not found. Installing rustup..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
  source "$HOME/.cargo/env"
fi

# 確保 cargo 在 PATH 中
source "$HOME/.cargo/env" 2>/dev/null || true

rustc --version || { echo "Failed to set up Rust"; exit 1; }
cargo --version || { echo "Failed to set up cargo"; exit 1; }

echo "  -> Setting default Rust toolchain to stable..."
# 若已有舊的 toolchain 目錄，備份並移除以避免衝突
if [ -d "$HOME/.rustup/toolchains/stable-x86_64-unknown-linux-gnu" ] && [ ! -d "$HOME/.rustup/toolchains/stable-x86_64-unknown-linux-gnu.bak" ]; then
  mv "$HOME/.rustup/toolchains/stable-x86_64-unknown-linux-gnu" "$HOME/.rustup/toolchains/stable-x86_64-unknown-linux-gnu.bak" || true
fi
rustup default stable || (rustup toolchain install stable --profile minimal && rustup default stable) || true

echo "  -> Adding Android targets..."
rustup target add aarch64-linux-android x86_64-linux-android || true

# ============================================
# 2. 檢查與安裝 Android SDK/NDK
# ============================================
echo "2) 檢查 Android SDK/NDK..."
SDK_ROOT="$HOME/Android/Sdk"
ANDROID_HOME="$SDK_ROOT"
export ANDROID_SDK_ROOT="$SDK_ROOT"
export ANDROID_HOME="$SDK_ROOT"

if [ ! -d "$SDK_ROOT/cmdline-tools/latest" ]; then
  echo "  -> Android SDK not found. Installing command-line tools..."
  mkdir -p "$SDK_ROOT"
  cd "$SDK_ROOT"
  
  CLT_ZIP="commandlinetools-linux-9477386_latest.zip"
  URL="https://dl.google.com/android/repository/${CLT_ZIP}"
  
  echo "     Downloading Android command-line tools..."
  if ! curl -fSL --output "$CLT_ZIP" "$URL"; then
    echo "     Failed to download. Trying alternate URL..."
    curl -fSL --output "$CLT_ZIP" "https://dl.google.com/android/repository/commandlinetools-linux-latest.zip"
  fi
  
  echo "     Extracting command-line tools..."
  unzip -q -o "$CLT_ZIP" -d cmdline-tools-tmp
  mkdir -p cmdline-tools/latest
  mv cmdline-tools-tmp/cmdline-tools/* cmdline-tools/latest/ || true
  rm -rf cmdline-tools-tmp
  
  cd "$REPO_ROOT"
fi

export PATH="$SDK_ROOT/cmdline-tools/latest/bin:$SDK_ROOT/platform-tools:$PATH"

if ! command -v sdkmanager >/dev/null 2>&1; then
  echo "  -> sdkmanager not found in PATH after extraction"
  exit 1
fi

echo "  -> Installing Android SDK packages..."
yes | sdkmanager --sdk_root="$SDK_ROOT" --install "platform-tools" "platforms;android-35" "build-tools;34.0.0" "ndk;28.2.13676358" "emulator" || true

echo "  -> Accepting SDK licenses..."
yes | sdkmanager --sdk_root="$SDK_ROOT" --licenses || true

echo "  -> Verifying Android SDK installation..."
sdkmanager --sdk_root="$SDK_ROOT" --list_installed || true

# ============================================
# 3. 檢查 pnpm 與 Node 依賴
# ============================================
echo "3) 檢查 Node 依賴..."
command -v pnpm >/dev/null 2>&1 || { echo "pnpm not found. Please install pnpm."; exit 1; }

echo "  -> Installing Node dependencies (pnpm install)..."
if ! pnpm install --silent; then
  echo "  -> pnpm install failed; retrying with --ignore-scripts..."
  pnpm install --silent --ignore-scripts || { echo "pnpm install (ignore-scripts) failed"; exit 1; }
fi

# ============================================
# 4. 初始化 Tauri Android 環境
# ============================================
echo "4) 初始化 Tauri Android 環境（pnpm exec tauri android init）..."
pnpm exec tauri android init || true

GWPROPS="src-tauri/gen/android/gradle/wrapper/gradle-wrapper.properties"
if [ -f "$GWPROPS" ]; then
  echo "5) 確認 gradle wrapper 使用鏡像源: $GWPROPS"
  sed -E -i.bak 's#distributionUrl=.*#distributionUrl=https\\://mirrors.cloud.tencent.com/gradle/gradle-8.14.3-bin.zip#g' "$GWPROPS" || true
  echo "  -> 已更新 $GWPROPS"
else
  echo "5) 找不到 $GWPROPS，跳過 gradle wrapper 替換。"
fi

# ============================================
# 5. 產生測試用 keystore（若不存在）
# ============================================
echo "6) 產生測試用 keystore（若不存在）..."
KEYSTORE="$REPO_ROOT/src-tauri/keystore.jks"
STOREPASS="password"
KEYPASS="password"
ALIAS="hula_test_key"

if [ -f "$KEYSTORE" ]; then
  echo "  -> keystore 已存在: $KEYSTORE"
else
  mkdir -p "$(dirname "$KEYSTORE")"
  echo "  -> 使用 keytool 生成 keystore: $KEYSTORE"
  keytool -genkeypair -v \
    -keystore "$KEYSTORE" \
    -storepass "$STOREPASS" \
    -keypass "$KEYPASS" \
    -alias "$ALIAS" \
    -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Test, OU=Dev, O=Dev, L=City, ST=State, C=CN" || {
    echo "  -> keytool 執行失敗，請確認已安裝 JDK 並可使用 keytool。"
    exit 1
  }
  echo "  -> keystore 生成完成。"
fi

# 為 Gradle 建立 keystore.properties
KS_PROPS="$REPO_ROOT/src-tauri/keystore.properties"
if [ ! -f "$KS_PROPS" ]; then
  cat > "$KS_PROPS" <<EOF
storeFile=keystore.jks
storePassword=$STOREPASS
keyAlias=$ALIAS
keyPassword=$KEYPASS
EOF
  echo "7) 已建立 $KS_PROPS"
else
  echo "7) $KS_PROPS 已存在，保留原檔。"
fi

# ============================================
# 6. 執行 Android 構建
# ============================================
echo "8) 執行 Android 構建（pnpm exec tauri android build）..."
echo "   注意：這個步驟會花費數分鐘到十多分鐘，並需要可以連網下載 Gradle／依賴..."
pnpm exec tauri android build || {
  echo "pnpm exec tauri android build 執行失敗，請檢查上方輸出訊息。"
  exit 1
}

# ============================================
# 7. 列出構建產物
# ============================================
echo ""
echo "=========================================="
echo "Android 構建完成！以下是構建產物："
echo "=========================================="
find src-tauri -type f \( -name "*.apk" -o -name "*.aab" \) -print || true

echo ""
echo "構建腳本執行完成。"
echo "若需要簽名 APK 或只輸出特定 ABI，請告知。"
