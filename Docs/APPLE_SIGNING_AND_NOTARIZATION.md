# Apple Developer 签名与公证接入

## 当前状态

顶屿已经能生成并自动验证 DMG，但当前候选包仍是 App ad-hoc 签名、DMG 未公证的开发者预览版。正式公开下载前必须完成 Developer ID 签名、Apple 公证和 staple。

## 账号和 Xcode 就绪后

1. 完成 Xcode 下载，打开 Xcode 一次并接受许可证、安装附加组件。
2. 在 `Xcode → Settings → Accounts` 登录加入 Apple Developer Program 的 Apple ID。
3. 在证书管理中创建或导入 `Developer ID Application` 证书。
4. 运行：

```bash
bash Scripts/check-signing-readiness.sh
```

只有输出 `Signing readiness: ready` 才进入正式构建。

## 保存公证凭据

使用 Apple 官方 `notarytool` 把凭据保存在登录钥匙串，不要写入仓库、脚本或 GitHub Issue：

```bash
xcrun notarytool store-credentials "TopIslet-Notary"
```

按提示使用 Apple ID、Team ID 和 App 专用密码，或使用 App Store Connect API Key。凭据只保存在本机钥匙串。

## 正式构建

先通过下列命令查看证书的完整名称：

```bash
security find-identity -v -p codesigning
```

然后构建 Developer ID DMG：

```bash
SIGN_IDENTITY="Developer ID Application: <证书名称> (<TEAM_ID>)" \
bash Scripts/build-release.sh
```

构建脚本会为 App 启用 hardened runtime 并签名 DMG。随后提交公证：

```bash
bash Scripts/notarize-release.sh \
  .build/release-artifacts/TopIslet-v0.1.0-arm64.dmg

REQUIRE_NOTARIZATION=1 \
bash Scripts/verify-release-dmg.sh \
  .build/release-artifacts/TopIslet-v0.1.0-arm64.dmg
```

`notarize-release.sh` 在 staple 后重新生成 SHA-256，因为 staple 会修改 DMG。公证失败时应查看 `notarytool log` 的具体原因，不能使用关闭 Gatekeeper 或移除 quarantine 的方式绕过。
