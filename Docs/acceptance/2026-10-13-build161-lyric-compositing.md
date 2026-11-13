# 第三轮：build161 换句重影与预检故障

本地候选，未推送或发布。第三轮goal保持active。

## 换句重影

build160真实All I Need展开截图在换句时捕捉到旧/新当前句与预告同时叠在同一阅读区域。实现为整块两行歌词的ID替换加反向位移/淡入淡出；频繁行变化会把退出和进入的两块卡片同时合成。

build161保留单个歌词阅读视图，移除整卡身份替换和进出位移，并隔离父层隐式动画。文字按当前源行更新，既有MarqueeClock换句重置、30Hz逐字渲染和长句滚动继续运行。没有改歌词来源、时间、字体、列宽或控制布局，也没有新增与实现镜像的单元测试。

357项既有回归通过，Release安装、40段一致性与严格签名通过。包与安装SHA256：`354c558933b00e9e59a5c8fc51fe4c8232d5cbb6b1f77efe9014818144caeced`。build160回滚保留 `.build/rollback/build160-before-lyric-compositing/顶屿.app`。

安装后Runaway真实展开截图显示单份当前句和预告；第二次不同正文/译文截图也没有此前旧卡叠影。它们是两张实际截图观察，不是120ms换句全过程的逐帧录像，不能据此宣布全部动态视觉验收完成。

## 实际控制与窗口状态

四次播放/暂停连续点击，约0.5秒间隔，目标paused→playing→paused→playing。控制接受25/18/24/7ms，状态确认216/213/213/218ms，专属源随后playing、rate1且时间前进。每次已有确认再进入下一次，因此不是未确认期间并发乱序验收，也不是物理键盘测试。较早的连点尝试被窗口变化/面板收起中断，未计入通过。

安装前后汽水PID61388、hidden=false、窗口minimized=false一致。没有重新打开、隐藏、取消最小化或重启汽水。

## 全屏后续（build160）

Chrome测试页在观察间消失，无法计入完成。改用Safari新测试标签播放W3C Sintel；原生窗口全屏后覆盖判定true、岛窗口0、进程1；Esc退出后false、岛1。仅关闭测试标签，保留原起始页。一次视频内全屏AX点击只暂停了视频、仍是普通窗口，未把它算作播放器全屏通过。

Ctrl-Left/Ctrl-Up没有证明Space切换。Mission Control入口超时，随后Escape恢复正常窗口。跨桌面仍未验证，不能把独立全屏窗口等价为“桌面2→视频全屏”。证据 `.build/qa/build160-round3/followup/`。

## 新故障，未计通过

build161日志03:29:43.996记录 `source_unavailable reason=control_probe_instance had_direct=1 had_media=1`，随后同曲变为has_duration=0、can_seek=0、默认播放标；实际专属源仍playing、rate1、duration326.033991、PID61388。已经有控制预检清空会话的确切调用路径，尚未捕获出错瞬间的AppKit查找细节，不能声称已证明是AppKit缓存缺陷或等同于build152旧问题。

该故障继续在build162修复。匿名日志、源位置和窗口元数据位于 `.build/qa/build161-round3/`。本轮不关闭整个稳定性goal。
