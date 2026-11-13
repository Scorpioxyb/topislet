# build54 最小化与桌面歌词并存的三键实测

阶段0未完成。起始c98635b，工作树干净，独立版本54。汽水同PID92624，窗口两个，独立minimized=0/1，前台im.manus.desktop。

全部输入使用CUA顶屿音乐卡片，从即时完整AX树识别命令按钮；不通过产品CLI发送播放命令。初次语义点击卡片未保持展开，随后使用新截图内坐标300,35展开并立即读取树/执行操作。此范围不作为全部命中区域通过。

- 初始曲春夏秋冬（kkluv, KKECHO）。实际暂停后AX按钮变“播放”，独立isPlaying=false、elapsedTime=75.562993。前台仍Manus、音乐窗口minimized=1。
- 暂停状态实际下一首，后续AX及截图曲名REDRED、歌手CORTIS、0:11/2:43、按钮暂停。切歌自动开始播放是汽水实际行为；不是顶屿自行额外发送播放命令的证据。
- 实际上一首，后续AX与截图返回春夏秋冬、原歌手、0:14/2:28。独立isPlaying=true、elapsedTime=27.682541847229004，前台Manus、两个窗口minimized=0/1、岛在屏1。
- 再次实际暂停，AX变播放，独立isPlaying=false、elapsedTime=54.165606。
- 实际恢复播放，AX变暂停，独立isPlaying=true、elapsedTime=67.56065700250244；前台Manus、窗口minimized=0/1，原PID不变。

本轮补齐build54在桌面歌词可见/主音乐窗口最小化时三键实际可用与基本反馈、未恢复或激活汽水窗口。未独立测量反馈延迟；切歌的外部源曲名未单独读取，仅顶屿AX/截图及播放时钟，不能声称混合元数据完整核验。结束音乐已确认播放。

未修改产品。本轮证据不能替代当前build54前台、关闭、异常恢复后三键、Desktop2/原生和独立伪全屏、动画80ms反转/逐帧黑边/全部点击区、生命周期性能及最终DMG。goal保持active。

CUA kernel reset，按精确可执行路径确认helper17725后TERM；进程表复查SkyComputerUseService/CUALockScreenGuardian均不存在。
