# build56 原窗口显示后 renderer 播放树恢复

起始汽水37785、顶屿37264，安装56。只读复核最小化主窗仍只有外壳，scanned46/candidate0、manualAccessibility=true。Finder CUA前往/Applications/汽水音乐.app选中应用，实际Cmd+O；无退出重启。随后元数据PID37785不变、主窗minimized0、前台com.soda.music，主窗树重新出现AXWebArea，独立控制diagnostic scanned302/candidate1。顶屿AX自动出现三键，无需点击重启恢复。

CUA基于实时卡片，歌曲shake it to the max时实际点击上一首，最终卡片为i'm not okay/JVKE。随后实际暂停，卡片变播放；独立primary verifiedQishuiSource=true/isPlaying=false/PID37785。暂停时点击下一首，动作调用成功，但本次即时卡片仍旧，下一次确认遇锁屏；不宣称该次换歌完成。锁屏后独立primary isPlaying=true/PID37785，可确认原进程恢复播放，不能据此证明下一首曲目。

锁屏context16748记录17:59:24Z screenLocked=true。CUA报告自动解锁失败，已请求手动解锁。测试期间有明确暂停区间，当前两小时性能记录不得称为“连续播放两小时”；仍可做混合使用生命周期/性能观察，持续播放门禁另需满足。原窗口显示改变了辅助功能树，支持最小化renderer退化而非PID死亡；仍未证明重建操作为初始原因或57预防效果。该次前台三键亦未完整通过（下一首最终曲目未确认）。

CUA reset后helper66594与guardian67659 TERM，ps核实清理。保持原顶屿、汽水，无安装/发布。
