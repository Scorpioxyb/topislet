# build56 DMG 候选内容验证

本轮未改产品，当前安装56。候选路径`.build/release-artifacts/build56/TopIslet-v0.1.3-arm64.dmg`，SHA256为`3b70138993e037ec56b9cdd4e50ef4c561190aa8651b26805e75f3d4054b5efb`，同目录sha256与candidate-receipt.json保留。

以/Applications安装版56复制应用，加入项目与第三方许可证后ad-hoc重签名。只读挂载旧常规0.1.3 DMG（独立确认其build30），仅复制.DS_Store布局；应用代码来自当前56。使用现有create-dmg-background.swift生成1320×800背景，Applications链接为/Applications，hdiutil创建UDZO候选。

现有verify-release-dmg.sh完整运行exit0：镜像校验、SHA256、顶层文件白名单、布局与背景、版本56/0.1.3、bundleID、最低macOS26、主程序arm64、vendor双架构、严格签名与三份许可证对照通过。不要求公证，本包未公证，不作为正式发布。

另行只读挂载候选，复制已安装与包内主程序到临时目录，仅移除临时副本签名；两份unsigned SHA256均为`5a53264cfa830c352cf48187b53c7896c49c0d337c2ce31538fa02b1b2e98d75`，确认代码逐字节一致。原应用签名未改变。

尝试CUA检查Finder安装界面时工具明确报告Mac锁屏且自动解锁失败，未得到视觉证据。已请求用户手动解锁；布局实际显示和DMG安装后启动仍待完成，不能以.DS_Store存在代替视觉验收。候选未安装、未上传发布。Goal保持active，其他稳定性门禁保留。

CUA reset后精确TERM helper40697与guardian40721，复查两服务均不存在。候选挂载卸载会话19035确认exit0；临时代码比较目录与打包staging移入Trash。旧布局源挂载也已卸载。保留候选及校验记录。
