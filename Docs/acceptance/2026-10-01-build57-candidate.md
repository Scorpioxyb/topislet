# build57 修正候选构建

> 后续代码核对确认57候选取自陈旧编译路径，已作废并移入Trash。下述版本/签名/布局证据不能证明57源码已装入包。当前待安装候选为更正后的58；详见2026-10-01-build58-corrected-candidate.md。

基于e60da31，Packaging/Info.plist构建号从56调整57，包含b414703歌词显示边界与e60da31最小化辅助功能树重建保护。swift build -c release --arch arm64正常完成126.05秒；前轮266测试通过，源码未再改。当前/Applications运行仍为56/PID37264，未终止、未替换、未启动候选。

候选`.build/release-artifacts/build57/TopIslet-v0.1.3-arm64.dmg`，SHA256 `396b6956bf912f14263fb24b1b9834290bcee72c5c8e89feec43c6b7690b90d3`；同目录sha256/candidate-receipt.json。复制当前应用资源，主程序替换为本轮Release binary，plist版本57，加三份许可证并ad-hoc重签。仅复用56 DMG的.DS_Store布局，背景由现有脚本生成1320x800，Applications链接/Applications。源挂载已卸载。整个流程未调用build-release.sh的Finder AppleScript UI段。

BUILD_NUMBER=57 verify-release-dmg.sh exit0，镜像与SHA、顶层白名单、背景布局文件、版本/ID/minOS26、主arm64/vendor双架构、严格签名和许可证对照通过。未公证、未发布；Finder视觉、安装启动、最小化控制退化回归与所有阶段0剩余门禁仍待。内容验证不等于实机修复成功。

两小时监测22112继续追踪原37264；666.079秒134样本时completed=false，p95CPU0.113%、最多1窗口、当前2子进程，不能以中途数据判断最终通过。保留候选用于监测完成后安装；不因打包成功封版。
