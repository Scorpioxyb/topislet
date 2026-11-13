# build58 候选代码校验及打包路径纠正

发现本轮57与首次58打包使用硬编码`.build/arm64-apple-macosx/release/MacBookIsland`，该文件mtime2026-09-05。当前swift build --show-bin-path实际返回`.build/out/Products/Release`，58编译产物mtime2026-10-01、4535328 bytes。此前版本、签名、布局检查未捕获陈旧程序，不能把这些包当修正候选。两个错误DMG及其checksum已移入Trash，58错误receipt保留invalid-candidate-receipt.json，57receipt标invalid；它们未安装发布。已纠正此前验收文档。

更正后58主程序来自构建工具报告的实际目录，源码功能基于a86ff23。重新签名与创建DMG，SHA256 `77b28878bd095a6e528f66cd1199a722252358efc2942abfee617339561a6bd8`。候选位置`.build/release-artifacts/build58/TopIslet-v0.1.3-arm64.dmg`。candidate-receipt.json记录来源路径、原始编译二进制SHA、镜像SHA、40个初始化Mach-O section哈希。签名修改load commands/签名元数据，全文件去签名比较不作为代码身份唯一方法。

新增Scripts/verify-release-binary.py比较全部初始化代码/数据sections，排除签名元数据及zero-fill。REFERENCE_BINARY指向实际58产物，verify-release-dmg.sh本轮再次运行exit0，实际挂载镜像中的40个sections一致；现有架构/minOS/签名/plist/布局/license/checksum门禁均通过。以旧硬编码路径程序作反例，比较明确exit1，拒绝旧代码。build-release.sh改为--show-bin-path并在签名后校验sections；verify-release-dmg.sh接受显式REFERENCE_BINARY启用镜像代码校验。bash -n、git diff --check、控制安全检查通过。未执行build-release.sh中AppleScript Finder UI段。

候选仍未安装/公证/发布，58Finder视觉与后台三键、最小化退化实机回归未完成。当前56/37264保持，监测22112继续；原始包内只读CLI读取曾返回37785播放true，但该次取旧程序，不能据此宣称58诊断路径实机通过。机器仍锁屏，解锁请求待回复。Goal保持active。


## 更正包的只读运行验证

随后只读挂载更正58，执行包内--qishui-status与--qishui-control-diagnostic，只保留分段、布尔、PID、扫描计数；不输出歌词、窗口URL或完整进程参数。primary verifiedQishuiSource=true/isPlaying=true/sourcePID37785；control trusted=true/manualAccessibility=true/scanned2/candidate0。当前锁屏，不能将稀疏树计数判为正常交互回归失败或成功。诊断命令完成后镜像卸载，ps确认仅原顶屿37264及原两perl子进程，无候选GUI实例或CUA残留。原始过滤输出/tmp/topislet-build58-corrected-runtime-status.log与/tmp/topislet-build58-corrected-runtime-controls.log；receipt补记录边界。

监测22112与context16748本轮均实际句柄确认live；469行CSV审计elapsed严格递增、最大间隔5.026秒、最大窗口1、当前子进程2、最长子增长10.019秒、无连续CPU高于5%区间。completed=false，不能算两小时完成或最终门禁通过。功能回归、安装、跨桌面/伪全屏和逐帧黑边仍未完成。
