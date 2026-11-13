# 61长观察终局与66安装、实机几何和后台控制

原资源29621、细子进程99272、事件88032、源采样7883全部由原handle返回exit0，真正终结；没有重开或提前终止。阶段0仍未通过，Goal active。

## 61终局不通过

资源.build/qa/build61-long-run.json：7200.010秒/1439样本，物理占用23970752→34767856bytes，增长45.0428%，超过原15%门槛，原violations明确保留该项。末RSS增长-14.0289%，平均CPU0.1047%/P950.1409%/最大0.1945%；连续CPU>5%时长0、线程增长5.016秒、粗子进程增长20.030秒、窗口最大/结束均1。原门槛没有修改，这轮性能不能通过。资源命令exit0仅表示完成报告，不表示验收成功。

细子进程7200.011秒/68398样本，最大采样间隔0.173373秒，baseline/end均37273及37274；1337不同额外PID各在已读取样本中出现一次，连续计数增长最长0.417997秒。PID首末观察跨度为0不等于真实存活0，细观察不擦除粗门槛。

事件7210.104秒/113事件，全部可信/playing，最大事件间隔398.712秒；不能证明间隔内连续播放。独立五秒源采样7204.240秒/1440样本，5次未核实（291/323/986/1160/1247），最大间隔5.019656秒。联合.build/qa/build61-joint-audit-final.json：allFourReportsTerminal=true，资源/源共同区间7073.690秒（117.895分钟），源起点晚126.266秒，共1413样本含5次空读，sampledEvidenceGatesSatisfied=false、continuousPlaybackAcceptanceProven=false。独立观察负载、手动切歌与交互均保留为限制，不将各自两小时写成共同完整两小时。

内存根因未证明。原观察结束后没有通过改baseline、删除样本、改变15%或把空读视为播放来判通过。

## 安装过程与实际进程

首次CUA读取61展开岛曾显示“播放控制暂不可用，自动重试”及主动恢复按钮。随后独立--qishui-control-availability=available、allowsControl=true，新的CUA树恢复三键；期间歌曲变化。缺少同步时间戳，不能推断原因或持续时长，不能宣布61所有切歌控制状态稳定。

尝试super+q没有退出；随后对岛系统对话框右键，读取实际上下文菜单并点击“退出顶屿”，CUA返回App quit，ps确认37272/37273/37274都消失，汽水仍37785。未点击源恢复/重启。正常退出没有精确计时，不能替代时限验收。

只读挂载66最终镜像，核实strict签名与版本66；按Trash政策移动旧/Applications/顶屿.app，再用ditto复制最终镜像内应用。新安装与镜像29条内容/权限/符号链接完全匹配、strict签名及40个初始化MachO段校验通过。binary SHA256 cc9bb1570186cfba0d9ca40bcaf2c9bd119ea849b52591730f5126ffaa26d69f。CUA getApp真实启动后主PID436、两个直接perl状态流442/443。receipt `.build/qa/build66-installed-receipt.json`；候选receipt只更新已验证安装/启动/几何/后台控制字段，动画完整/completion/中断/全屏/final仍false。镜像已detach，61核实回滚副本保留。

## 66实机窗口几何

只调用verify-island-window-animation.swift --observe-only --samples-output，被动观察20秒；所有输入由CUA点击实际岛和收起控件。7639样本、平均381.91Hz、最大间隔27.674ms，只有1窗口，中心误差0.5pt、顶边漂移0，377×35↔460×191，严格几何观察通过；无崩溃。`.build/qa/build66-passive-animation-raw.csv`及summary保留。

两次展开中间采样跨度180.390/181.438ms，末起点样本到首终点样本185.417/189.808ms；收回中间跨度149.466ms、末起点到首终点156.623ms。这些不支持240±16.7/180±16.7ms时长门禁通过。没有同步输入时间或像素帧，不能把采样跨度写成精确渲染时长；仍须更强取证及驱动核查。没有实测80ms反向10次、逐帧黑边、减少动态效果或全屏中断。

## 66隐藏+最小化控制

实际CUA依次点击暂停、播放、下一首、上一首。独立已安装--adapter-status前后白名单快照确认trusted=true、同汽水37785；暂停isPlaying=false、恢复true，下一首指纹改变，上一首返回原指纹。所有快照源hidden=true/mainMinimized=true/mainWindowCount=1，前台bundle均com.apple.Safari。文件 `.build/qa/build66-controls-{before-pause,after-pause,after-play,after-next,after-previous}.json` 和 hidden-controls-summary。没有保存原曲名/歌手/歌词/URL，只有指纹和白名单数量/播放字段。状态辅助Swift探针最初==.success语法编译失败，补空格后成功；失败时未写控制证据文件。

此项是操作前后证据，不能声称全程鼠标/前台零变化或准确延迟；也不能替代源前台、隐藏未最小化、关闭、AX故障、源重启和其他媒体零误控。66自身完整长观察、内存、歌词后台新歌、全屏/Desktop2、视觉/命中区/提醒/生命周期和宣传截图仍待完成。

CUA已reset，对核实basename为SkyComputerUseService的PID1406发送TERM；随后ps验证SkyComputerUseService/CUALockScreenGuardian均无残留。436/442/443与汽水37785继续运行。未推送、Tag、公证或发布。
