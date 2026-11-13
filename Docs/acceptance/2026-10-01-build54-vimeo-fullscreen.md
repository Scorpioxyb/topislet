# build54 Vimeo 视频全屏观察

用户要求后续不再用百度网盘测试，流媒体验收改用 Safari 的公开 Vimeo 视频 `https://player.vimeo.com/video/1084537`。本轮未继续操作百度网盘。YouTube 页面要求登录确认，未登录；Vimeo 成功加载 Big Buck Bunny，先静音再播放。

安装版本仍为 0.1.3 build54，未修改产品代码。CUA 使用播放器语义“全屏”按钮，而非 Safari 窗口全屏按钮。两次点击后的 AX 均出现独立对话框和“退出全屏”按钮，播放进度推进。

同时运行 120 秒的只读 WindowServer 观察器，每约 100ms 采样。检测策略来自现有 FullScreenSuppression.swift。记录如下（相对于观察器启动的秒数）：

| 时间 | 覆盖屏幕 | 顶屿屏幕窗口数 |
| --- | --- | --- |
| 0.382 | false | 1 |
| 24.170 | true | 1 |
| 24.306 | true | 0 |
| 29.172 | false | 0 |
| 29.387 | false | 1 |
| 81.374 | true | 1 |
| 82.106 | true | 0 |
| 104.022 | false | 0 |
| 104.238 | false | 1 |

可确认两次覆盖期间顶屿隐藏，覆盖解除后恢复。第二次覆盖约 22.65 秒。以上是采样差值，不能作为可靠的性能上限。播放器后来恢复普通窗口，第二次最终为暂停；未明确操作“退出全屏”，退出原因未建立，不声称完整的主动退出验收通过。

限制：观察器采样的前台 bundle 始终为 Manus，Safari 窗口筛选以英文 ownerName 匹配，得到空列表。另一个并行只读窗口检查返回前台 Safari、顶屿屏幕窗口数 0、汽水 PID92624、窗口最小化 0/1。这些时间与 CUA 的后台操作行为不能完全对齐，因此覆盖窗口尚未独立绑定到 Safari，不能据此宣布流媒体持续全屏及 Desktop2 全部通过。截图随后显示普通 Safari 视频窗口。该项继续保持待验收，后续采用流媒体，不再采用百度网盘。

观察器正常结束，CUA kernel reset，核对 SkyComputerUseService 精确 PID22791 后 TERM；pgrep 复核 SkyComputerUseService 与 CUALockScreenGuardian 均不存在。没有发布或推送。阶段0 Goal 保持 active，build54 最终 DMG 及其他未完成门禁仍保留。
