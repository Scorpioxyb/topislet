# build56 Vimeo 原生视频全屏隐藏与主动退出恢复

安装56、起始HEAD b86a69d，本轮未改产品。继续Safari公开Vimeo Big Buck Bunny测试页，未操作百度网盘。视频原先暂停且静音，点击播放后截图与AX确认播放进度推进。

独立观察器使用当前FullScreenSuppression.swift原始策略，按NSRunningApplication bundleIdentifier得到Safari PID10095、顶屿PID37264，随后只读WindowServer元数据。没有按本地化ownerName匹配，没有记录窗口标题或URL。约100ms采样120秒，记录状态变化；正常结束observerCompleted=true。

| 观察器秒数 | Safari在屏窗口 | 覆盖屏幕 | 顶屿在屏窗口数 |
| --- | --- | --- | --- |
| 0.104 | 856,34,854,991 | false | 1 |
| 46.555 | 0,33,1710,1074 | true | 0 |
| 46.881 | 0,34,1710,1073（另有顶部33pt窗口） | true | 0 |
| 80.262 | 856,34,854,991 | false | 0 |
| 80.363 | 856,34,854,991 | false | 1 |

CUA点击播放器语义“全屏”（未点击Safari窗口绿灯），AX出现对话框及“退出全屏”。进入后独立安装版--fullscreen-status确认hasCoveringWindow=true。约22秒后重新读取AX仍为全屏对话框、退出控件，视频进度从1:55至2:17。实际点击即时编号21“退出全屏”，观察器随后出现普通窗口滑入、覆盖窗口消失、顶屿恢复。独立--fullscreen-status为false，AX最终为普通标准窗口及“全屏”按钮。

Safari PID对应覆盖窗口从46.555至80.262，约33.707秒；这段观察器状态没有出现顶屿重现。主动退出后约一个采样间隔恢复，不能把100ms采样差值声称为可靠性能上限。原生全屏的普通窗口滑出/滑入可以确认系统空间转换，但未识别Desktop2，不把此项当作明确桌面2回归或独立伪全屏通过。

测试视频主动暂停，AX为播放键；保留原标签页。结束独立读取前台Safari，汽水PID37785保持、窗口2/最小化0与1、顶屿在屏1。独立状态CLI返回isPlaying=true、elapsedTime81.02851891517639、PID37785，同时附加unknown，因此不声称所有源读取一致。可确认视频测试后后台汽水原进程仍播放，未重启汽水。

CUA reset后精确helper39222 TERM，复查SkyComputerUseService与CUALockScreenGuardian均不存在。Goal保持active，伪全屏/明确桌面切换、黑边逐帧/快速反向/全点击区、长时间性能与最终DMG继续待验收；无发布推送。
