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
# 4. 清理旧的 Android 生成文件并重新初始化
# ============================================
echo "4) 清理旧的 Android 生成文件..."
# 删除旧的 gen/android 目录以确保图标等资源被重新生成
if [ -d "$REPO_ROOT/src-tauri/gen/android" ]; then
  echo "  -> 删除 src-tauri/gen/android 目录..."
  rm -rf "$REPO_ROOT/src-tauri/gen/android"
fi

echo "5) 初始化 Tauri Android 環境（pnpm exec tauri android init）..."
pnpm exec tauri android init || true

GWPROPS="src-tauri/gen/android/gradle/wrapper/gradle-wrapper.properties"
if [ -f "$GWPROPS" ]; then
  echo "6) 確認 gradle wrapper 使用鏡像源: $GWPROPS"
  sed -E -i.bak 's#distributionUrl=.*#distributionUrl=https\\://mirrors.cloud.tencent.com/gradle/gradle-8.14.3-bin.zip#g' "$GWPROPS" || true
  echo "  -> 已更新 $GWPROPS"
else
  echo "6) 找不到 $GWPROPS，跳過 gradle wrapper 替換。"
fi

# ============================================
# 5. 產生測試用 keystore（若不存在）
# ============================================
echo "7) 配置簽名 keystore..."

# 優先使用 GitHub Secrets 中的證書
if [ -n "${KEYSTORE_BASE64:-}" ]; then
  echo "  -> 檢測到 GitHub Secrets 中的證書，進行解碼..."
  KEYSTORE="$REPO_ROOT/src-tauri/release.keystore"
  echo "$KEYSTORE_BASE64" | base64 -d > "$KEYSTORE"
  
  # 從環境變數讀取證書信息
  STOREPASS="${KEYSTORE_PASSWORD:-bp@2025secure}"
  KEYPASS="${KEY_PASSWORD:-bp@2025secure}"
  ALIAS="${KEY_ALIAS:-bp-key}"
  
  echo "  -> 已從 GitHub Secrets 解碼證書到: $KEYSTORE"
else
  echo "  -> 未檢測到 KEYSTORE_BASE64 環境變數，使用本地測試證書..."
  KEYSTORE="$REPO_ROOT/src-tauri/keystore.jks"
  STOREPASS="password"
  KEYPASS="password"
  ALIAS="hula_test_key"

  if [ -f "$KEYSTORE" ]; then
    echo "  -> 測試 keystore 已存在: $KEYSTORE"
  else
    mkdir -p "$(dirname "$KEYSTORE")"
    echo "  -> 使用 keytool 生成測試 keystore: $KEYSTORE"
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
    echo "  -> 測試 keystore 生成完成。"
  fi
fi


# 為 Gradle 建立 keystore.properties
KS_PROPS="$REPO_ROOT/src-tauri/keystore.properties"
# 總是重新生成 keystore.properties 以確保使用最新配置
KEYSTORE_FILENAME="$(basename "$KEYSTORE")"
cat > "$KS_PROPS" <<EOF
storeFile=$KEYSTORE_FILENAME
storePassword=$STOREPASS
keyAlias=$ALIAS
keyPassword=$KEYPASS
EOF
echo "8) 已更新 $KS_PROPS (使用 $KEYSTORE_FILENAME)"

# ============================================
# 6. 執行 Android 構建
# ============================================
echo "9) 執行 Android 構建（pnpm exec tauri android build）..."
echo "   注意：這個步驟會花費數分鐘到十多分鐘，並需要可以連網下載 Gradle／依賴..."
pnpm exec tauri android build || {
  echo "pnpm exec tauri android build 執行失敗，請檢查上方輸出訊息。"
  exit 1
}

# ============================================
# 7. 簽名 APK（若存在 unsigned APK 且 keystore 存在）
# ============================================

sign_apks_if_needed() {
  # 決定 SDK 路徑（先用環境變數，否則使用預設）
  SDK_ROOT="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"

  # 使用與前面配置一致的 KEYSTORE 路徑和密碼
  SIGN_KEYSTORE="$KEYSTORE"
  SIGN_STOREPASS="$STOREPASS"
  SIGN_KEYPASS="$KEYPASS"
  
  if [ ! -f "$SIGN_KEYSTORE" ]; then
    echo "  -> 找不到 keystore ($SIGN_KEYSTORE)，跳過自動簽名。"
    return 0
  fi

  # 找到 build-tools 版本（優先 34.0.0，否則挑選最高版本）
  if [ -d "$SDK_ROOT/build-tools/34.0.0" ]; then
    BT_VER="34.0.0"
  else
    BT_VER=$(ls -1 "$SDK_ROOT/build-tools" 2>/dev/null | sort -V | tail -n1 || true)
  fi
  BT_DIR="$SDK_ROOT/build-tools/$BT_VER"

  ZIPALIGN="$BT_DIR/zipalign"
  APKSIGNER="$BT_DIR/apksigner"

  # 回退到 PATH 中的工具（若絕對路徑不存在）
  if [ ! -x "$ZIPALIGN" ]; then
    ZIPALIGN=$(command -v zipalign || true)
  fi
  if [ ! -x "$APKSIGNER" ]; then
    APKSIGNER=$(command -v apksigner || true)
  fi

  if [ -z "$ZIPALIGN" ] || [ -z "$APKSIGNER" ]; then
    echo "  -> 無法找到 zipalign 或 apksigner（檢查 Android build-tools 是否安裝）。"
    return 1
  fi

  echo "  -> 使用 build-tools: $BT_DIR"
  echo "  -> zipalign: $ZIPALIGN"
  echo "  -> apksigner: $APKSIGNER"

  # 尋找 unsigned APK
  mapfile -t UNSIGNED_APKS < <(find src-tauri -type f -name "*-unsigned.apk" -print 2>/dev/null || true)
  if [ ${#UNSIGNED_APKS[@]} -eq 0 ]; then
    echo "  -> 找不到 *-unsigned.apk，若已有簽名 APK 則跳過。"
    return 0
  fi

  for APK in "${UNSIGNED_APKS[@]}"; do
    echo "  -> 發現 unsigned APK: $APK"
    ALIGNED="${APK%.apk}-aligned.apk"
    SIGNED="${APK%.apk}-signed.apk"

    echo "     對齊 APK -> $ALIGNED"
    "$ZIPALIGN" -v -p 4 "$APK" "$ALIGNED" || { echo "     zipalign 失敗：$APK"; return 1; }

    echo "     簽名 APK -> $SIGNED"
    "$APKSIGNER" sign --ks "$SIGN_KEYSTORE" --ks-pass pass:$SIGN_STOREPASS --key-pass pass:$SIGN_KEYPASS --out "$SIGNED" "$ALIGNED" || { echo "     apksigner 簽名失敗：$ALIGNED"; return 1; }

    echo "     驗證簽名："
    "$APKSIGNER" verify --print-certs "$SIGNED" || { echo "     apksigner 驗證失敗：$SIGNED"; return 1; }

    echo "     已生成簽名 APK: $SIGNED"
  done

  return 0
}

echo ""
echo "=========================================="
echo "Android 構建完成！現在檢查是否需自動對齊與簽名 APK..."
echo "=========================================="

# 嘗試自動簽名（若 keystore 可用且有 unsigned apk）
if sign_apks_if_needed; then
  echo "自動簽名步驟完成（若有需要並成功）。"
else
  echo "自動簽名步驟發生錯誤，請手動簽名或檢查 build-tools。"
fi

echo ""
echo "構建產物列表："
find src-tauri -type f \( -name "*.apk" -o -name "*.aab" \) -print || true

# ============================================
# 8. 上傳到 GitHub Release
# ============================================
upload_to_github_release() {
  echo ""
  echo "=========================================="
  echo "上傳 APK 到 GitHub Release (koola-cloud/bp-app tag: test)"
  echo "=========================================="

  # 檢查是否有 GitHub Token
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo "  -> 未檢測到 GITHUB_TOKEN 環境變數，跳過上傳到 GitHub Release。"
    echo "  -> 提示：在 CI 環境中設置 GITHUB_TOKEN 以啟用自動上傳。"
    return 0
  fi

  # 檢查是否安裝 gh CLI
  if ! command -v gh >/dev/null 2>&1; then
    echo "  -> GitHub CLI (gh) 未安裝，嘗試安裝..."
    if command -v apt >/dev/null 2>&1; then
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
      sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
      sudo apt update
      sudo apt install gh -y
    else
      echo "  -> 無法自動安裝 gh CLI，請手動安裝：https://cli.github.com/"
      return 1
    fi
  fi

  # 配置 gh 使用 GITHUB_TOKEN
  export GH_TOKEN="$GITHUB_TOKEN"

  # 目標倉庫和標籤
  TARGET_REPO="koola-cloud/bp-app"
  TAG_NAME="test"
  RELEASE_NAME="Build test"

  echo "  -> 目標倉庫: $TARGET_REPO"
  echo "  -> 標籤: $TAG_NAME"
  echo "  -> Release 名稱: $RELEASE_NAME"

  # 查找簽名的 APK
  SIGNED_APK=$(find src-tauri -type f -name "*-signed.apk" -print -quit 2>/dev/null || true)
  
  if [ -z "$SIGNED_APK" ]; then
    echo "  -> 未找到簽名的 APK，查找未簽名的 APK..."
    SIGNED_APK=$(find src-tauri -type f -name "*-unsigned.apk" -print -quit 2>/dev/null || true)
  fi

  if [ -z "$SIGNED_APK" ]; then
    echo "  -> 錯誤：未找到任何 APK 文件"
    return 1
  fi

  echo "  -> 找到 APK: $SIGNED_APK"
  
  # 生成新的文件名（包含時間戳）
  TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
  APK_FILENAME="bp-test-${TIMESTAMP}.apk"
  
  echo "  -> 上傳文件名: $APK_FILENAME"

  # 檢查 Release 是否存在
  if gh release view "$TAG_NAME" --repo "$TARGET_REPO" >/dev/null 2>&1; then
    echo "  -> Release '$TAG_NAME' 已存在，刪除舊資產並上傳新文件..."
    # 刪除舊的 APK 文件（如果存在）
    gh release delete-asset "$TAG_NAME" "bp-test-*.apk" --repo "$TARGET_REPO" --yes 2>/dev/null || true
    # 上傳新文件
    gh release upload "$TAG_NAME" "$SIGNED_APK#$APK_FILENAME" --repo "$TARGET_REPO" --clobber
  else
    echo "  -> Release '$TAG_NAME' 不存在，創建新的 Release..."
    # 創建新的 Release
    gh release create "$TAG_NAME" "$SIGNED_APK#$APK_FILENAME" \
      --repo "$TARGET_REPO" \
      --title "$RELEASE_NAME" \
      --notes "自動構建的測試版本 APK

構建時間: $(date '+%Y-%m-%d %H:%M:%S')
構建腳本: scripts/android_build_test.sh

## 下載
- APK: $APK_FILENAME

## 安裝說明
1. 下載 APK 文件
2. 在 Android 設備上啟用「未知來源」安裝
3. 安裝 APK

**注意**: 這是測試版本，僅用於內部測試。" \
      --prerelease
  fi

  if [ $? -eq 0 ]; then
    echo "  -> ✓ 成功上傳到 GitHub Release!"
    echo "  -> Release URL: https://github.com/$TARGET_REPO/releases/tag/$TAG_NAME"
  else
    echo "  -> ✗ 上傳失敗，請檢查錯誤信息"
    return 1
  fi

  return 0
}

# 執行上傳（如果有 GITHUB_TOKEN）
upload_to_github_release || true

echo ""
echo "構建腳本執行完成。"
echo "若需要調整簽名 keystore 或只輸出特定 ABI，請告知。"
