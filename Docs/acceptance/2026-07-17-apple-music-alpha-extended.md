# 2026-07-17 Apple Music Alpha 扩展回归

## 目标

在公开 build 18 上扩大 Apple Music Alpha 样本，验证普通歌曲、跨专辑封面、播放 / 暂停、电台无内嵌封面回退，以及汽水与 Apple Music 同时运行时的来源选择。

## 环境

- 顶屿：`0.1.1 (18)`，Bundle ID `io.github.scorpioxyb.topislet`，安装于 `/Applications/顶屿.app`。
- 源码基线：`e6ed67c9c30ff5dc3af8e7b3bb28d8973787d078`。
- Apple Music 与汽水音乐同时运行；Apple Music 自动化和汽水辅助功能均已授权。
- 顶屿音乐诊断仅在读取内部时间线时临时开启，结束后恢复关闭。

## 普通歌曲和播放状态

- Apple Music 从无当前歌曲的 `stopped` 状态开始，顶屿没有伪造歌曲。
- 播放 `Janice STFU - Drake` 后，定向状态读取返回 `availability=ready`、`artworkDataBytes=142345`，元数据与原生封面在 `238ms` 内一起返回。
- 岛内暂停后，按钮切换为播放，Apple Music 原生状态为 `paused`；`84.93s` 的位置在额外等待 1.5 秒后保持不变。
- 岛内恢复后，按钮切回暂停，Apple Music 原生状态为 `playing`，进度继续推进；未观察到旧图标闪回或暂停位置倒退。

## 切歌和跨专辑封面

- 从 `Janice STFU` 切换到同专辑的 `B's On The Table - Drake & 21 Savage`，歌名、歌手和封面保持同一曲目快照；定向读取为 `256ms`，封面 `142345 bytes`。
- 再切换到 `玻璃 - Gareth.T` 时，内部时间线记录：
  - 定向控制在 `170ms` 返回接受；
  - 新歌名和歌手在 `453ms` 发布；
  - Apple 公共目录封面在 `613ms` 就绪，完整带封面 UI 在 `619ms` 发布；
  - 目录封面为 `89499 bytes`，后续独立原生读取也能返回该曲目的 `429875 bytes` 内嵌封面。
- 切换过程中没有出现新歌名配旧歌手；目录封面到达时只合并图片，不重置播放时间轴。

## 电台回退

- 启动 ATEEZ 电台时，Apple Music 先短暂发布只有标题的 `ATEEZ` 占位流，没有歌手、专辑或内嵌封面。适配器保持无封面，不执行模糊猜测。
- 电台进入实际歌曲 `BOUNCY (K-HOT CHILLI PEPPERS) - ATEEZ` 后，定向元数据读取为 `262ms`。
- 原生封面缺失时，Apple 公共目录精确匹配返回 `100946 bytes` 封面，总补齐时间约 `1008ms`。
- 汽水暂停后，岛自动切到 Apple Music，并显示实际电台歌曲与歌手；汽水重新播放后按产品优先级恢复为汽水来源。

## 结论与清理

- 普通歌曲、跨专辑、播放 / 暂停、电台精确封面回退和双来源优先级在当前账号与网络环境通过。
- 本轮没有发现需要修改播放逻辑的失败；Apple Music 多账号、弱网和长时间电台稳定性仍需继续积累样本，Alpha 等级不变。
- `swift test`：110 项通过。
- 测试结束后 Apple Music 已退出，汽水恢复播放，顶屿诊断开关恢复关闭。
- Computer Use 会话已通过 `js_reset` 完全退出，没有遗留鼠标控制。
