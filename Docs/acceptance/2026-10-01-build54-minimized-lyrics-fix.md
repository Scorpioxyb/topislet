# 最小化播放器被桌面歌词窗口干扰

阶段0未完成，起始7181d90、安装53。CUA点击汽水最小化后，后续独立窗口检查确认两个窗口minimized分别0和1；即时AX标题为桌面歌词。展开顶屿显示播放控制暂不可用、自动重试提示，无三键。

只读AX逐窗口核验：桌面歌词AXStandardWindow、AXMain=1、AXFocused=0、AXMinimized=0；汽水音乐AXStandardWindow、AXMain=0、AXFocused=0、AXMinimized=1。旧53控制诊断scanned=496、candidateCount=0。

代码的primary判定接受main/focused或唯一标准窗口。歌词窗口也是标准窗口，导致最小化主播放器不是唯一标准窗口，从而无法通过健康候选门槛。修复只在唯一标准窗口fallback中排除精确标题“桌面歌词”（去首尾空白），其他窗口仍保留；控件组唯一性、时间上下文、位置、enabled/press检查没有放宽。

新增标题判定回归检查，完整262测试、控制安全检查、diff check通过。修复后debug构建同实机诊断scanned=496、candidateCount=1，命中汽水音乐，main=false、focused=false、minimized=true、relativeY=.956。

该证据证明控件发现恢复，不证明实际三键动作成功。版本准备54，Release打包安装结果和实机三键另补。build53候选包已不是最新修复版本，不是最终交付。

Release打包安装进程exit0，安装路径/Applications/顶屿.app严格签名验证通过，独立版本读取54。旧安装经move-to-trash保留回滚路径。CUA启动54显示当前音乐卡片；随后展开并尝试暂停的调用报native pipe closed，没有确认按钮动作。独立检查前台im.manus.desktop，汽水仍PID92624、两个窗口minimized=0/1、isPlaying=true、elapsedTime=85.93175880700684。不能计入实际暂停或三键通过。

第二次CUA reset后精确识别helper16690并TERM，最终进程检查结果以复查为准。阶段0及当前54的控制、全屏、动画、生命周期与最终DMG继续待验收。

CUA reset后精确TERM helper12502，进程表复查两个辅助服务均不存在。未遗留暂停模拟；没有实际发送下一首，因为即时树没有该按钮。
