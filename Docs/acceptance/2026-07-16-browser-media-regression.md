# 2026-07-16 浏览器媒体并存回归

## 环境

- 顶屿：`0.1.1 (17)`，安装于 `/Applications/顶屿.app`。
- 汽水音乐：`com.soda.music`，辅助功能语义控件已就绪。
- Chrome：`150.0.7871.115`。
- Safari：macOS 26.5.2 系统版本。
- Chrome 视频：由本机已有 H.264/AAC 录屏生成的 15 秒临时 M4V。
- Safari 视频：本机已有 45.7 秒 HEVC/AAC 录屏，通过 `localhost` 临时页面播放。
- 临时页面、媒体副本和浏览器测试配置在回归后全部移入废纸篓。

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

## Safari 带声音媒体焦点

启用 Safari“允许远程自动化”后，SafariDriver 成功连接 `26.5.2`。按实际冲突顺序先播放汽水，再启动 Safari 有声视频；MediaRemote 全局读取明确返回：

- `bundleIdentifier=com.apple.WebKit.GPU`
- `parentApplicationBundleIdentifier=com.apple.Safari`
- `title=TopIslet Safari Media P0`
- `playbackRate=1`
- `duration=45.7`

与此同时，顶屿 `--adapter-status` 持续返回：

- `verifiedQishuiSource=true`
- `sourceBundleIdentifier=com.soda.music`
- 汽水歌曲、播放态、进度和封面均可读取。

在每项控制前重新确认 Safari 为系统当前媒体，再依次执行汽水播放/暂停、下一首、上一首：

- 三次 `semanticQishuiControlSent=true`，汽水播放态或歌曲按命令变化。
- Safari 每次操作后均为 `paused=false`，时间线持续推进并正常循环。
- 前台应用在每次调用前后均为 `com.apple.Safari`。
- 原子探针记录每次控制调用前后鼠标 `pointerDelta=0.0,0.0`。
- 切歌稳定后，汽水歌名、歌手、专辑和封面恢复为完整一致状态。

结论：Safari 带声音视频抢占系统媒体焦点时，汽水同步和三种控制隔离通过。

## 结论

- Chrome 浏览器 P0 冲突回归：通过。
- Safari 静音视频隔离：通过。
- Safari 带声音媒体焦点：通过。
- 回归后汽水恢复暂停；SafariDriver、本地测试服务器和 WebDriver 会话均已关闭，临时页面与媒体副本已移入废纸篓。
- 本轮未使用 Computer Use，没有遗留鼠标控制会话。
