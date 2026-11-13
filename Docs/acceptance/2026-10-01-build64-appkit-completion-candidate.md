# build64 AppKit完成回调候选

原资源29621/细子进程99272/事件88032/播放采样7883逐一poll仍live，安装保持61/37272/两stream37273/37274，汽水37785。本轮开始2750秒左右、结束3340秒左右，观察未终结；footprint相对原始基线约41.9%，两次播放采样空读仍保留。未安装、重启、故障注入或新建观察取代旧handle。

## AppKit驱动尝试的失败证据

QA要求AppKit completion正常收尾，63的displayLink终点实现与该条款不一致。尝试NSAnimation非阻塞驱动、override currentProgress提交frame、animationDidEnd收尾。编译期间Swift6隔离错误已解决；加入实际callback测试后进度/完成均未触发。默认/显式runloop模式、NSApplication.shared、独立filter及mainThread=true+RunLoop pump均没有证明该路径可用。全套同步pump还阻塞其他异步测试，出现额外时限失败；没有将那些失败当其他产品逻辑回归。

失败日志在/tmp/topislet-appkit-animation-driver-tests*.log、/tmp/topislet-appkit-driver-*.log；最后试验源备份.build/qa/appkit-driver-experiment/。该路径没有安装、不声称实机失败根因，也没有放进最终候选。试验新文件已按Trash政策移动；随后产品main恢复63源码再做64修正，没有遗留失败实验测试。

## 当前候选64

恢复NSAnimationContext.runAnimationGroup+completionHandler，IslandPanel明确override animationResizeTime返回本次240/180ms，而不是仅依赖context.duration。SDK NSWindow.h明确setFrame:display:animate:总时长由animationResizeTime决定；这支持候选方向，但不能证明animator所有内部调用或实际像素都已正确。

IslandPanel.setFrame提交前通过IslandAnimationFrame整点取整宽高，再由目标midX/maxY计算origin，替代resize通知后补改origin。AppKit完成只通过animationID/currentMode门禁释放target状态，不做正常完成snap。反向/隐藏先零时长提交当前观测frame替换旧窗口动画，再清理旧owner；隐藏提交目标frame，退出/拓扑刷新仍清理。零时长取消旧动画的实际可靠性及每帧是否走override必须安装后原始采样/反向10次/全屏中断验证；不能仅由源码宣称解决466/566ms或1pt漂移。

删除63独立时间轴生产文件及4项独立时间轴测试（移Trash，Git历史可恢复），避免不再执行的时间轴被当新驱动证据。新增2项针对实际使用的IslandAnimationFrame：1001个分数插值固定顶边/中心、整点尺寸、三态/外接屏终点不变。原completion generation测试继续存在；总272项通过（/tmp/topislet-build64-final-tests.log），控制安全/diff通过。测试数量下降不是删失败来判通过：被撤回驱动测试及其失败完整留存，当前AppKit驱动的实机完成仍未通过。

Release ARM64 16.70秒；候选.build/release-artifacts/build64/TopIslet-v0.1.3-arm64.dmg SHA256 365426cc1eb1af05a0d274139fc8c6b1946190b8837ae8a081dc42afbcd5d1b3。独立verify-release-dmg BUILD_NUMBER64/实际SwiftPM .build/out/Products/Release/MacBookIsland，签名/40初始化代码数据段一致/版本/布局通过。receipt installed/launched/realMachineAnimation/appkitCompletion/interruptions/finalCandidate均false。63和62历史保留，64为最新待安装候选。

Goal active。下一步骤：等待61原观察终结完整审核（原baseline不变），保留已验证61回滚，从最终64镜像安装并实际验证AppKit时长/中心顶边/80ms反向10次/隐藏释放/源控制等。所有门禁完整通过前不封版，未推送/Tag/公证/发布。本轮没有CUA，未改变系统权限或设置。
