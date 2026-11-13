# build54 退出、清理与重开

安装版54，本轮未修改产品。起始主PID16724，直接子进程16727/16728。Python核对精确主可执行路径和子进程集合后发送SIGTERM，约20ms轮询，三进程全部消失耗时0.123346458秒，没有残留。该值只证明本次信号退出，不代表菜单退出耗时。

CUA冷启动后主29340、两条stream-client为29343/29344，均归属主进程。卡片显示当前歌曲。首次右键菜单在卡片自然更新后元素编号失效，退出未执行；刷新后重新右键，核对“退出顶屿”编号7并点击。CUA随后noWindowsAvailable；独立ps核对三个PID全部不存在，pgrep确认无MacBookIsland或mediaremote-adapter.pl。菜单动作未独立计时，不声称菜单退出一秒门槛已通过。

再次CUA启动，主30649、状态流30653/30654，两个父PID均30649。使用comm与精确参数路径过滤，避免把诊断shell自身误算为状态流。确认一个主进程、两条状态流。独立WindowServer/AX读取：前台Codex，汽水原PID92624、窗口2、最小化0/1、顶屿在屏窗口1。CUA显示歌曲。未点击播放控制，不声称本轮覆盖三键功能。

CUA reset后精确helper29314 TERM，复查SkyComputerUseService与CUALockScreenGuardian均不存在。控制安全脚本通过。长时间性能、全部停止源/重绑、全屏跨桌面、80ms反向/逐帧黑边/全命中区域及最终DMG仍未完成，Goal保持active。
