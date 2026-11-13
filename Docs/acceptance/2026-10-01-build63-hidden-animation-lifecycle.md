# build63 隐藏期间动画生命周期候选与61内存观察

上一轮已提交窗口显示同步时间轴候选62，本轮继续逐一poll原观察29621/99272/88032/7883，全部live。当前安装保持61/37272，汽水37785持续播放；没有中途安装、重启、故障注入或调整权限。

## 隐藏的动画资源清理

NSWindow.displayLink在窗口不属于显示器时可能不回调，不能依赖末帧释放target。因此repositionPanel在隐藏/全屏抑制时直接完成尺寸，不新建displayLink；updatePanelVisibility即将orderOut时若有未完成时间轴，先使generation失效、invalidate/清空displayLink与transition/id、提交目标frame/content size，再隐藏。显示器空间或全屏变化后的恢复不依赖旧回调。此项是源代码审查发现的候选边界，不是62安装版已复现的故障。

274项测试通过（/tmp/topislet-build63-tests.log）；控制安全与diff检查通过。ARM64 Release16.52秒；.build/release-artifacts/build63/TopIslet-v0.1.3-arm64.dmg SHA256 a9ecea6f76643f9a0e10cbc0142aa8a8cf0c56bb2ff1661f5c77fff2cc8d9a9f。独立verify-release-dmg BUILD_NUMBER63/实际SwiftPM Release二进制，签名/布局/版本及40初始化代码数据段一致通过。candidate-receipt标明installed/launched/realMachineAnimation/hiddenLifecycle/finalCandidate均false。63为下次待安装候选，62保留历史，不能用单元测试替代63实际全屏中断/退出/反向验收。

## 61内存与子进程中期证据

.build/qa/build61-memory-interim-analysis.json保存此次读取的统计，不改动原资源报告。前五个300秒区间physical footprint中位数约23.08/23.85/24.44/24.44/24.59MiB；1500秒区间25.10MiB、1800秒区间30.66MiB、2100秒区间30.83MiB。表现为一次台阶上升，不能仅凭曲线断言泄漏、缓存或动画是原因。原基线约22.86MiB；约40分钟仍高约37%，结束门禁15%仍适用，不重新选更高基线以宣布通过。

只读vmmap -summary 37272保存.build/qa/build61-vmmap-midrun.txt：当时footprint31.1MiB，malloc bytes allocated13.4MiB，没有起始同口径vmmap所以不能判定哪个zone增长或证明对象泄漏。已有解码封面缓存4项/总1MiB，媒体流原图缓存24项；尚不能把内存台阶归因于缓存，没有为假设修改生产缓存。

细子进程观察约354个增长区间，最长约0.212秒；五秒采样连续两行child3时分别是不同短寿命PID，不能推断同一第三进程持续10秒。原资源summary的maximumSustainedChildGrowthSeconds10.0118保留，不改变判定方法或用细观察抹去已产生的违规。终结后分别审核。

播放5秒观察仍保留两次自然切歌附近unverified空读，独立事件流仍trusted/playing；中期不是两小时连续播放证明。没有新的CUA输入，本轮复查无SkyComputerUseService/CUALockScreenGuardian。Goal active，待原观察正常终结后审核、保留rollback并安装63实际验收。
