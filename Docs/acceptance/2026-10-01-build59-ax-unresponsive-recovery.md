# build59 不响应后自动恢复与三键

起始安装59、顶屿PID6687、汽水37785，主窗口已关闭且媒体暂停。CUA访达应用“打开”语义动作未使主窗出现；随后GoTo /Applications/汽水音乐.app、Return、Cmd+O显式恢复。独立AX主窗min0/歌词min0、原PID37785、前台汽水。顶屿展开后自动出现三键，未点击恢复/重启。

Python先核对37785精确可执行路径，再SIGSTOP。独立stat=T；40秒finally保护SIGCONT，终端session40416正常exit0，实际40.020秒后恢复，独立最终stat=S。仅暂停主进程，不声称全音频子进程冻结。无权限、设置或AX属性写入。

故障期间CUA树与实际截图确认三键撤下，显示“正在确认汽水播放控件是否可用。”及显式重启入口；没有点击该入口。CONT后未先运行控件诊断或恢复CLI，CUA树自动恢复三键。

恢复后CUA实际播放，可信专属媒体状态Direct With It/isPlaying=true/PID37785；实际下一首，可信NOT FOR ME/王嘉尔/true；实际上一首，可信Direct With It/true；实际暂停，可信Direct With It/false/17.277954秒。原汽水进程连续，主窗min0/桌面min0。

访达Raise没有稳定改变前台；独立检查恢复后front=com.soda.music。本次证明当前59前台主窗可读时不响应故障解除后的自动恢复及三键实际可用，不算最小化/隐藏后台故障恢复，也未测取消/超时反馈或可靠恢复延迟。CUA动作后第一份树可能仍为旧歌，歌曲结果以上述独立可信源为准。

其后发现hover展开后直接控件操作不改变mode，旧hover返回任务仍可收回。该源码问题在build60修正，59证据不自动升级到60；后续当前版本门禁继续验收。
