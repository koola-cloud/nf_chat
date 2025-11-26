# Android 签名证书配置指南

## 📦 证书信息

已生成正式签名证书，证书信息如下：

- **证书文件**: `bp-release.keystore` (已生成在项目根目录)
- **Key Alias**: `bp-key`
- **Store Password**: `bp@2025secure`
- **Key Password**: `bp@2025secure`
- **有效期**: 10000 天 (约 27 年)

## 🔐 GitHub Secrets 配置

请在 GitHub 仓库中设置以下 Secrets：

### 1. 进入仓库设置
访问: `https://github.com/koola-cloud/nf_chat/settings/secrets/actions`

### 2. 添加以下 Secrets

#### KEYSTORE_BASE64
```
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
```

#### KEYSTORE_PASSWORD
```
bp@2025secure
```

#### KEY_ALIAS
```
bp-key
```

#### KEY_PASSWORD
```
bp@2025secure
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
   - 本地证书文件 `bp-release.keystore` 已添加到 `.gitignore`
   - 请妥善保管证书文件和密码
   - 不要将证书文件提交到 Git 仓库

2. **证书备份**:
   - 请将 `bp-release.keystore` 文件备份到安全位置
   - 丢失证书将无法更新已发布的应用

3. **构建模式**:
   - 如果环境变量中没有 `KEYSTORE_BASE64`，脚本会自动使用本地测试证书
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
