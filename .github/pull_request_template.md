## 变更内容

<!-- 说明这个 PR 解决的一个明确问题。 -->

## 验证

- [ ] `swift build`
- [ ] `swift build -c release`
- [ ] `bash -n Scripts/package-app.sh Scripts/build-release.sh`
- [ ] `plutil -lint Packaging/Info.plist`
- [ ] `git diff --check`
- [ ] 涉及 UI 时已附同设备、同状态的前后截图
- [ ] 涉及媒体控制时已验证前台 App、鼠标和其他播放器不受影响

## 隐私与第三方依赖

- [ ] 不包含个人路径、真实日历/提醒内容、账号数据、token 或第三方 App 解包产物
- [ ] 新增或修改第三方依赖时已记录来源、版本、许可证和构建方式
