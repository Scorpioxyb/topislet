# 2026-07-16 浏览器媒体并存回归

## 环境

- 顶屿：`0.1.1 (17)`，安装于 `/Applications/顶屿.app`。
- 汽水音乐：`com.soda.music`，辅助功能语义控件已就绪。
- Chrome：`150.0.7871.115`。
- Safari：macOS 26.5.2 系统版本。
- 视频：由本机已有 H.264/AAC 录屏生成的 15 秒临时 M4V；临时页面、视频和 Chrome 测试配置在回归后全部移入废纸篓。

## Chrome 带声音媒体焦点

独立 Chrome 测试实例自动循环播放带声音视频。MediaRemote 全局读取明确返回：

- `bundleIdentifier=com.google.Chrome`
- `duration=15`
- `playbackRate=1`

与此同时，顶屿 `--adapter-status` 继续返回：

- `verifiedQishuiSource=true`
- `sourceBundleIdentifier=com.soda.music`
- 汽水歌曲、播放态、进度和封面均可读取。

依次执行汽水播放/暂停、下一首、上一首：

- 三次 `semanticQishuiControlSent=true`。
- Chrome 视频时间在每次操作前后继续推进，始终为 `playing`。
- 前台应用始终为 `com.google.Chrome`。
- 每次操作前后鼠标坐标完全一致。
- 汽水播放态和歌曲按命令变化，稳定后元数据完整一致。

结论：Chrome 带声音视频抢占系统媒体焦点时，汽水同步和三种控制隔离通过。

## Safari 初步回归

Safari WebDriver 无法建立会话，系统返回必须先在 Safari 设置的“开发者”中启用“允许远程自动化”。未擅自修改该系统设置。

改用 Safari 允许的静音自动循环播放后，辅助功能树连续读取到：

- 视频按钮为“暂停”，说明处于播放态。
- 已播放时间连续推进并在 15 秒后循环。
- 顶屿三种汽水控制均成功。
- Safari 始终保持前台，鼠标位置不变，视频继续推进。

静音自动播放没有注册为系统 MediaRemote 当前媒体，因此只能证明 Safari 播放期间没有 UI 误触，不能代替带声音媒体焦点回归。

## 结论

- Chrome 浏览器 P0 冲突回归：通过。
- Safari 静音视频隔离：通过。
- Safari 带声音媒体焦点：待产品负责人手动播放一次后完成最终确认。
- Computer Use 本轮初始化返回 `Transport closed`；没有遗留 Computer Use、Chrome 测试实例、Safari、SafariDriver 或临时测试进程。
