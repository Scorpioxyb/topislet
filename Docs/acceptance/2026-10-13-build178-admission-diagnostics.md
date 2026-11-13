# 第三轮：build178 播放证据拒绝原因

[build177](2026-10-13-build177-stable-music-surface.md)真实四连切歌反证说明3.3秒证据保护仍未覆盖所有路径。为避免再次推测原因而扩大期限，本候选保持原条件、仅把process播放证据返回的bool映射成固定原因：invalid_budget/deferred/missing_receipt/future_receipt/expired/missing_pid/retired_pid/missing_snapshot/unverified/cached/snapshot_pid/unknown_playback/sample_changed/expected_pid/fresh。原bool接口仍只有fresh为true，原PID/sample/年龄/非cached/已知状态门禁顺序未改。

MediaAdapter在原因/direct是否有播放证据/origin变更时记录playback_admission_evidence，不记录曲名、歌词、时间值、窗口信息。timeline_ui_state继续区分字段降级，数据日志仍去重，不新增来源读取或系统输入。

编译首次失败（sampleOrigin没有rawValue）已更正为枚举名称字符串，保留失败日志evidence-focused.log。最终全套391项通过，控制安全脚本及diff检查通过。Release/package安装退出0、40段一致、严格签名通过；源码/安装0.1.3 build178、PID20800；安装/package二进制SHA256均`d04cdaa7470752774006ac2b65f88015e41ecbde06e4a00db09d3c386b35cb71`，177回滚保留。

CUA实际打开折叠→紧凑→展开后，AX有当前歌词、暂停按钮和进度。随后同步90秒观察开始，四连切歌尝试返回Mac锁定错误；不得把该轮记录当作完成或失败的音乐控制验收。待观察进程自然退出后保留原数据，不因窗口失效覆盖同一prefix。锁屏后AX窗口状态minimized=unavailable不解释成源窗口变更。当前源PID仍61388，未重启、激活、隐藏或取消最小化汽水。

当前goal仍active。177有/无歌词连续性短窗通过，但未知AX假暂停和时长清洗反证仍开放；178仅提供归因诊断，不宣称修复这些故障。物理键盘起点、音频/像素同步、后台歌词局限和长期性能均未关闭。未提交、推送或发布。

收尾：两观察及日志stream均退出0，原数据保留。1275 AX样本与4个源包中只有3个明确目标PID，均不作为锁屏交互验收。独立get-client确认PID61388、playing=1、rate=1、elapsedTimeNow约96.996秒、duration191.033秒；只证明收尾源状态，不证明音频。CUA已reset，专属SkyComputerUseService按完整可执行路径退出；确认SkyComputerUseService/CUALockScreenGuardian均不存在。未关闭Codex或任务宿主。
