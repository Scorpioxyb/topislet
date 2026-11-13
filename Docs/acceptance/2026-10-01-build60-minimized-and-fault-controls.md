# build60 最小化后台三键与不响应恢复

只读CGSession复查已解锁、Chrome前台，顶屿18925/汽水37785原进程存活，工作树干净。Goal锁屏阻断已解除，保持active。CUA实际点击汽水最小化按钮，独立AX主窗min1/桌面歌词min0、hidden=false，可信媒体Direct With It暂停52.723132秒。

实际岛播放后可信专属媒体true、Direct With It61.427531秒；实际下一首后NOT FOR ME/王嘉尔/true；实际上一首后Direct With It/true；实际暂停后false33.185820秒。每次独立窗口检查汽水37785、主窗min1、桌面min0、Chrome前台。由此通过60本次最小化后台三键往返，没有汽水重开、取消最小化或替换进程。

展开后的树曾回到紧凑态，造成一次next missing，未发送该次命令；重新展开后完成有效下一首。为调查收回，在具有既有权限的只读listenOnly event tap中记录30秒鼠标按下位置及异步交付时指针位置，正常终止30.049秒。期间多次点击落在岛外，不能将混合交互中的收回归因于hover修正失败，也不能据此证明点击固定展开通过。未增加权限、生成输入或采集窗口标题/URL。日志/tmp/topislet-build60-click-points.log只用于本次诊断，不纳入版本控制；完整hover→点击→移出且无outside点击仍待验收。原位指针不变/其他流媒体进度不变尚无证明。

补最小化后台不响应故障：Python先核对源PID37785的精确执行路径，SIGSTOP后独立stat=T；40秒finally保护SIGCONT，实际40.013092秒，session2658正常exit0，最终stat=S。仅暂停主进程，不声称音频子进程全部冻结。原始故障保护记录.build/qa/build60-minimized-ax-fault.json。

故障期间CUA确认三键撤下，显示“正在确认汽水播放控件是否可用。”；未点击重启连接，没有预先运行恢复/控制诊断CLI。CONT后CUA确认三键自动重新出现，实际播放可信true；下一首NOT FOR ME/true；上一首Direct With It/true；实际暂停Direct With It/false25.037418秒。每次独立主窗min1、桌面min0、同PID37785；这些恢复后检查前台Codex，故不宣称固定Chrome。可以证明60本次最小化后台不响应解除后自动恢复及实际三键可用；不涵盖隐藏、权限撤销、所有异常、取消/超时或可靠恢复时延。

最终汽水保持最小化且暂停，未自动还原。CUA kernel reset并TERM精确helper，ps确认无SkyComputerUseService/CUALockScreenGuardian残留。故障保护与只读观察均已终结，不存在待等待任务。receipt补两项verified，finalCandidateVerified仍false。Goal未完成，不推送、公证或发布。
