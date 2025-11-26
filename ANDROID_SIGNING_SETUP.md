# Android 签名证书配置指南

## 📦 证书信息

本项目使用 GitHub Secrets 存储签名证书信息，本地开发使用测试证书。

**生产环境证书信息（存储在 GitHub Secrets 中）：**
- **证书文件**: 通过 `KEYSTORE_BASE64` 环境变量传递
- **Key Alias**: 存储在 `KEY_ALIAS` Secret 中
- **Store Password**: 存储在 `KEYSTORE_PASSWORD` Secret 中  
- **Key Password**: 存储在 `KEY_PASSWORD` Secret 中

**本地测试证书（自动生成）：**
- **证书文件**: `keystore.jks`（自动生成，已在 .gitignore 中）
- **Key Alias**: `hula_test_key`
- **密码**: `password`

## 🔐 GitHub Secrets 配置

请在 GitHub 仓库中设置以下 Secrets：

### 1. 进入仓库设置
访问: `https://github.com/koola-cloud/nf_chat/settings/secrets/actions`

### 2. 添加以下 Secrets

#### KEYSTORE_BASE64
生成方法：
```bash
# 生成新的签名证书
keytool -genkeypair -v \
  -keystore release.keystore \
  -storepass YOUR_STORE_PASSWORD \
  -keypass YOUR_KEY_PASSWORD \
  -alias YOUR_KEY_ALIAS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Your Name, OU=Your Org Unit, O=Your Org, L=City, ST=State, C=CN"

# 转换为 Base64
base64 -w 0 release.keystore
```

#### KEYSTORE_PASSWORD
```
YOUR_STORE_PASSWORD
```

#### KEY_ALIAS
```
YOUR_KEY_ALIAS
```

#### KEY_PASSWORD
```
YOUR_KEY_PASSWORD
```

## 🚀 使用方法

### 本地构建（使用测试证书）
```bash
bash scripts/android_build_test.sh
```

### GitHub Actions 构建（使用正式证书）
在 GitHub Actions workflow 中设置环境变量：

```yaml
- name: Build Android APK
  env:
    KEYSTORE_BASE64: ${{ secrets.KEYSTORE_BASE64 }}
    KEYSTORE_PASSWORD: ${{ secrets.KEYSTORE_PASSWORD }}
    KEY_ALIAS: ${{ secrets.KEY_ALIAS }}
    KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
  run: bash scripts/android_build_test.sh
```

## 📝 注意事项

1. **证书安全**: 
   - 本地证书文件 `*.keystore` 和 `*.jks` 已添加到 `.gitignore`
   - 请妥善保管证书文件和密码
   - 不要将证书文件提交到 Git 仓库

2. **证书备份**:
   - 请将生产证书文件备份到安全位置
   - 丢失证书将无法更新已发布的应用

3. **构建模式**:
   - 如果环境变量中没有 `KEYSTORE_BASE64`，脚本会自动生成并使用本地测试证书
   - 测试证书仅用于开发测试，不应用于发布

## 🔄 更新证书

如需更新证书，重新生成后：
1. 将新证书转换为 Base64: `base64 -w 0 new-keystore.jks`
2. 更新 GitHub Secrets 中的 `KEYSTORE_BASE64`
3. 同时更新相关的密码和别名

## ✅ 验证签名

构建完成后，可以验证 APK 签名：
```bash
$ANDROID_SDK_ROOT/build-tools/34.0.0/apksigner verify --print-certs app-signed.apk
```
