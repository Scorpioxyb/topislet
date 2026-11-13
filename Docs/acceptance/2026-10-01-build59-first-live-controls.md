# build59 首次启动、后台可见窗三键及歌词卡片

恢复Goal后独立CGSession screenLocked=false。通过CUA getApp启动已安装/Applications/顶屿.app，主PID6687，两状态流6690/6691；机器原汽水PID37785不变。已安装plist59。只读控制诊断accessibilityTrusted=true/manualAccessibilityEnabled=true/scanned367/candidateCount1，没有新增TCC或系统权限操作。

实际CUA展开音乐卡片，截图显示X/王嘉尔及真实歌词“Gon get it get it”。实际暂停后图标为播放，独立--qishui-status主源verified=true/isPlaying=false/PID37785，前台Chrome。恢复后独立isPlaying=true，前台仍Chrome。后续Direct With It/Swimming Paul, Beaux Neptune卡片截图显示当前句及中文翻译。当前歌词辅助功能聚合标签只暴露“当前歌词”而非逐行正文，正文用截图确认；屏幕截图不是逐帧黑边验收。

实际下一首后独立可信主源NOT FOR ME/王嘉尔、播放true；实际上一首后Direct With It/Swimming Paul, Beaux Neptune、播放true。两次AX窗口形态独立核对front=com.google.Chrome、main minimized=0、desktop minimized=0、hidden=false、汽水PID37785。由此证明59后台主窗未最小化情况下三键实际可用，不能升级为最小化/关闭/错误恢复通过。

测试期间卡片曾自动收回，导致旧索引失效（play missing/用户界面变化/一次offscreen错误）；重新读取紧凑态并在同调用内展开后解析当前按钮完成操作。最早offscreen下一首时随后歌曲自然更替，不用这次错误作为成功证据；最终下一首/上一首以独立曲目往返证明。收回原因尚未确认，不能称所有命中区和点击固定展开已通过；继续对照hover触发/手动展开规则核验。

CUA内核reset后终止精确服务PID，后续ps确认无CUA残留；未结束顶屿或汽水。receipt更新launched=true、runningPID6687、后台可见窗三键及歌词渲染布尔，finalCandidateVerified仍false。原56两小时资源未通过信号不改变；59最终长稳尚未启动。剩余门禁见STAGE0_CURRENT_GATES，Goal保持active，不测试百度网盘。
