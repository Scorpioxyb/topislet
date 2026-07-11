# QA 检查清单

## 构建与安装

- `swift build` 能通过。
- `Scripts/package-app.sh` 能生成并安装 `/Applications/MacBook 灵动岛.app`。
- `codesign --verify --deep --strict --verbose=2 "/Applications/MacBook 灵动岛.app"` 通过。
- `file "/Applications/MacBook 灵动岛.app/Contents/Resources/MediaRemoteAdapter/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter"` 同时包含 `arm64` 和 `x86_64`。
- 双击 App 或 `open "/Applications/MacBook 灵动岛.app"` 后顶部灵动岛出现，设置面板可打开。
- 正常运行进程不包含 `--preview-mode` 或 `--preview-feature` 参数。
- 安装包包含 `qishui-targeted-control.py`，且不包含 `qishui-focused-control`、短暂激活汽水或全局媒体键实现。
- 安装包 `Info.plist` 包含 `NSCalendarsFullAccessUsageDescription` 和 `NSRemindersFullAccessUsageDescription`。

## 日历与提醒事项

- 首次启动不主动弹出日历或提醒事项权限；`--eventkit-status` 只读取当前状态，不触发授权。
- 设置的“日程”页可分别申请日历和提醒事项权限；一项拒绝、撤权或关闭时，另一项及汽水音乐继续正常工作。
- 日历授权后，未来 10 分钟内的定时日程会进入事件队列；全天日程不展示。
- 提醒事项授权后，只展示具有具体时间且刚到期 5 分钟以内的未完成事项；无时间提醒和大量历史逾期事项不补发。
- 展开音乐、拖动进度、seek 或媒体控制 pending 期间，EventKit 普通事件只排队，不抢占当前交互。
- 两个不同日程或提醒事项分别排队，不因同属“日历”或“提醒事项”而合并；同一事项在 30 秒轮询中不会重复展示。
- 关闭开关或在系统设置中撤权后，正在后台返回的旧查询结果不得重新投递；岛内尚未展示的对应事项应取消。
- 点击 EventKit 提醒中的“打开”可启动系统日历或提醒事项；找不到对应 App 时不显示无效按钮。
- 日历库较大时，连续展开、收起和拖动仍保持流畅，30 秒轮询不得造成周期性主线程卡顿。

## 汽水音乐同步

- 汽水音乐播放时，`--adapter-status` 显示 `verifiedQishuiSource=true`，适配器子进程参数包含 `stream-client com.soda.music`。
- 灵动岛显示真实歌名、歌手、封面。
- 切歌后歌名、歌手、封面原子更新，不能出现新歌名配旧歌手或旧封面。
- 播放/暂停后按钮状态能回读，不长期停留在 pending。
- 进度条只使用汽水专属 MediaRemote Adapter 的可信 `elapsedTime / duration`；AX 列表时间不得覆盖主进度。
- 播放中连续读取 `--adapter-status` 时，`elapsedTime` 和 `progress` 应稳定递增，不应倒退或跳到旧歌进度。
- 拖动后不显示调试文案；媒体焦点被视频占用时，进度拖动不得误控视频播放器。

## QuickPlayer/QuickTime 并存回归

- 先播放汽水音乐，再打开 QuickPlayer/QuickTime 播放视频。
- 灵动岛继续从 `com.soda.music` 客户端更新，不能切成视频信息、空状态或假数据。
- 视频播放器占用系统媒体焦点时，点击播放/暂停、上一首、下一首不会控制视频播放器。
- 设置面板中能看到媒体焦点冲突的解释，主胶囊不显示调试备注。
- 视频播放、暂停和关闭前后，汽水同步不需要手动恢复。

## 抖音/浏览器视频并存回归

- 打开 Chrome 或 Safari 中的抖音视频页面，同时保持汽水音乐运行。
- 灵动岛点击展开、收起、设置入口仍然响应。
- `ps -p $(pgrep -x MacBookIsland | head -n 1) -o %cpu` 稳态不应长期高于 10%。
- 启动后不应自动弹出设置窗口；再次打开 App 或菜单点击“设置...”才出现设置窗口。
- 关闭设置/校准窗口后，CPU 应回落，不应留下隐藏窗口持续重排。
- 主界面不应因为视频页面频繁媒体事件而持续重排卡顿。
- 抖音播放并占用系统媒体焦点后，歌名、歌手、封面、播放态和进度仍从汽水专属流自动更新。
- 点击播放/暂停、上一首、下一首时，优先直接发送给 `com.soda.music` 的 MediaRemote client；仅在该通道不可用时尝试汽水 PID 内的唯一语义 AX 控件。抖音播放状态和进度零变化。
- 控制前后前台 App 不变，鼠标位置不变；不得出现窗口闪动、固定坐标点击或鼠标事件。
- 媒体焦点被视频占用时，进度拖动不得控制视频播放器；没有汽水专属 seek 确认时应明确阻断。

## 汽水专属控制

- 汽水音乐单独播放时，播放/暂停、上一首、下一首、进度拖动都命中汽水。
- 抖音/QuickTime/浏览器视频播放时，播放/暂停、上一首、下一首仍应命中汽水 client；视频不能被暂停或切换。
- 汽水音乐未运行时，控制按钮不得误控当前系统媒体。
- 汽水窗口最小化、隐藏或 AX 树未初始化时，只能在唯一识别安全控件后执行；否则应安全失败并保持当前界面。
- 300ms 内连续三次切歌，岛不能收起，最终歌曲应等于汽水真实结果，旧回包不能覆盖新回包。
- 控制点击 50ms 内有按压反馈；超过 120ms 才显示等待环，成功或失败后等待态消失。

## 交互与视觉

- 胶囊与摄像头模组垂直位置匹配，底部不露出摄像头遮挡区域。
- 正常启动和展开时只有当前活动，不出现音乐、计时器、提醒三个固定标签。
- 普通提醒在紧凑/折叠状态短暂展示后恢复此前模式和汽水最新状态。
- 展开音乐、拖动进度或媒体控制 pending 期间，普通提醒不得替换当前内容；只允许显示动态消息提示。
- 计时器仅在用户通过菜单启动后接管，计时结束提醒处理完毕后恢复汽水。
- 连续点击展开/收起没有明显位置跳动。
- 紧凑、展开和再次收起后，顶部窄岛与展开面板中心线误差不超过 1pt；音乐和计时器控制组不残留左偏或右侧异常空白。
- 展开 / 收回逐帧不得出现半透明灰色矩形、完整空黑大面板停顿、内容纵向压扁或隐藏 Body 窗口拦截底层点击。
- 展开态点击外部能自动恢复折叠/紧凑形态。
- 主界面不出现“已同步”“来源”“Adapter”等调试文案。
- 背景保持透明，胶囊外没有发灰或不干净的边。

## 安全硬门禁

- 控制期间前台 App 切换次数为 0。
- 控制期间鼠标坐标变化为 0，也没有合成鼠标事件。
- 代码和安装包中没有全局媒体键控制、`qishui-focused-control` 或固定坐标兜底。
- client 定向通道不可用且语义控件无法唯一识别时失败，不把命令转发给系统当前媒体源。
- 不使用 OCR、屏幕录制、汽水 ASAR 修改、MITM 或 token 提取。

## 诊断命令

```bash
.build/debug/MacBookIsland --qishui-status
.build/debug/MacBookIsland --adapter-status
.build/debug/MacBookIsland --mediaremote-status
.build/debug/MacBookIsland --eventkit-status
.build/debug/MacBookIsland --qishui-targeted-control playPause
pgrep -af 'mediaremote-adapter.pl.*stream-client.*com.soda.music'
```
