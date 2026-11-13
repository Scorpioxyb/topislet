# 第三轮：build177 音乐展开视图连续性

175唯一缺进度AX样本发生在歌词首次出现附近，原有日志未出现对应数据降级，因此不能追认为已证明的可见进度消失。代码中ExpandedMusic会在歌词有/无之间替换整个LyricExpandedMusic/ControlOnlyExpandedMusic，连控制区、进度row及其scrub状态一起重建。

177将两种布局合并为一个稳定HStack/VStack，保持左侧控制和MusicProgressRow的结构身份，只在读取区域内替换歌词/空态。原尺寸、间距、偏移和分界线高度按既有条件更新，不改音乐来源/同曲歌词门禁/定向控制。删除两个重复布局结构的代码属于重构，不删除本地文件。

新增timeline_ui_state匿名事件，只有曲目指纹或duration/elapsed是否存在、canSeek、播放可信度变化时记录；不记录时间值、歌词/曲名/歌手、不新增来源读取。

391项回归、控制安全脚本、diff检查通过；Release打包/安装退出0、40段一致、严格签名通过。安装0.1.3 build177、PID19524，安装/package二进制SHA256均`6f65f3fd3db058bcd6ec842e1e0a6c2cf7fd3655730ac371526011c5b2330286`；回滚176保留。

实机90秒三方记录`.build/qa/build177-round3/provenance/summary.json`：1552展开AX样本、无paused/缺progress；有歌词→无歌词→有歌词，播放按钮token=1、进度token=2始终不变。10个源包均PID61388、playing。两次next accepted=6/16ms；第一首最终数据约1395ms，第二首679ms；第二首核验词级歌词network约2067ms。截图无歌词态保留控制与时间轴。支持视图连续性，未证明音频/逐帧像素/长期稳定。

为了覆盖原快速切歌故障，随后独立60秒记录rapid-summary.json：1048展开样本中6个假暂停、7个无progress；9源包全部目标PID playing。四次实际间隔0.402/0.684/0.393秒，4/4 accepted。日志08:05:24.466显示未知AX占主显示（has_duration/elapsed=0、playback_known=0）约282ms；08:05:27.393源同曲无时长约67ms后补回。该失败属于数据选择/清洗路径，不能归因视图重建，仍保留原反证。

本候选播放证据3.3秒保护未彻底解决未知AX回落；后续仅增加具体拒绝原因诊断，避免继续凭推断调整期限。第三轮goal active，未提交、推送或发布。
