# build60 信号退出、计时活动及全屏恢复

起始解锁，工作树干净。精确核对安装执行路径和两直接子进程后SIGTERM：主31236、stream31238/31239在99.190ms全部消失，汽水37785保留；原始.build/qa/build60-sigterm-exit.json。CUA重新启动32053/两stream32054/32055/单窗口，再SIGINT后62.144ms全部消失、汽水保留；原始.build/qa/build60-sigint-exit.json。5ms目标采样、真实单调耗时，均在1秒内。随后CUA启动32173、stream32174/32175，后续独立单窗口确认。

实际右键设置→活动→选择5分→开始专注→显示计时器，关闭设置后岛显示专注计时中04:40。没有改日历/提醒事项开关或权限，也未修改真实日程。复用已有Safari公开Vimeo Big Buck Bunny静音暂停页，实际播放并进入播放器全屏；AX对话框/退出全屏，进度5:44至6:44。安装CLI hasCoveringWindow=true，实际退出后false，视频暂停并保留静音。

只读WindowServer观察器按Safari PID10095、顶屿32173绑定。120.089秒/1138样本，最大gap163.048ms，正常session42203 exit0；.build/qa/build60-vimeo-timer-120s.json。覆盖内容区X0/Y33/W1710/H1074样本14.751至75.752秒、584样本，全部岛0。退出后普通Safari框、岛1。CUA岛确认专注计时中02:47，活动未丢失；此为当前60原生流媒体全屏/退出活动恢复，不能代替明确Desktop2、独立伪全屏、底层所有点击或另一服务。

计时器自然推进01:21→00:14，最终通知“时间到/计时器已经结束”。CUA实际点击关闭完成提醒，岛恢复Direct With It/Swimming Paul, Beaux Neptune紧凑卡片。可信媒体源同歌暂停21.900564秒、汽水37785/hidden=true/main min1。独立顶屿仅32173/在屏窗口1、X666/Y-1/W377/H35。完成了本次五分钟自然结束与用户关闭提醒后的音乐还原；普通系统提醒的临时展示/恢复和源退出重绑仍需单独验收。观察期间其他前台应用变化，不宣称固定Safari或指针不变。

CUA kernel reset并精确TERM服务，复查两种helper无残留。监测/计时都已终结，音乐暂停，未启动两小时长稳。receipt补本轮verified但finalCandidateVerified=false；未发布，Goal active。
