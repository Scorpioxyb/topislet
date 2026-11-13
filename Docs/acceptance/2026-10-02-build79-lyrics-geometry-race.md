# build79 歌词几何重排竞态修复

状态：本地 Release 候选，Goal 仍进行中；未封版、未发布。

## 新证据

build78 安装后实机观察到：顶屿 AX 标签已经显示“原文，译文”，但窗口仍保持无歌词的 377pt 紧凑宽度；有歌词内容出现在窄栏中。代码审计发现歌词 `@Published` 监听直接在 `willSet` 回调里调用 `repositionPanel`，此时 `model.music` 仍是旧值；同时监听只映射“是否有歌词”，同样有歌词的换句不会触发几何重排。

## 修复

- 监听改为比较完整的 `MusicLyricPresentationState`，主句或译文变化都会产生新值。
- 几何重排通过 `DispatchQueue.main.async` 延后一轮，读取已经提交的 `model.music`，保证 `compactWidth` 与 `CompactMusic` 使用同一状态。
- 增加状态变化测试，确认两首不同歌词都保持可用但状态不相等。

## 验证

- `swift test --quiet`：287 项通过。
- `git diff --check`：通过。
- `Scripts/package-app.sh`：Release 构建、40 段代码/资源比对、签名和安装通过。
- `/Applications/顶屿.app`：`0.1.3 (79)`，严格签名验证通过。
- 安装后只读截图已保存到 `.build/qa/build79-lyrics/01-build79-wide-state.jpeg`，尺寸 1202×70 像素；当前歌词与译文完整落在歌词宽档内，窗口不再停留在无歌词的窄档。
- 汽水音乐仍只做只读观察，不点击、不切歌、不控制播放。
- 后续 build80 将歌词快照新鲜度上限收紧到 0.9 秒，避免旧句在 AX 暂时无活动行时继续占据 UI。

## 尚未关闭门禁

- 同一有歌词曲目的长句完整滚动周期。
- 长句完整滚动周期、当前活动行归属、切句延迟、资源占用、多屏、全屏、黑边和 Reduce Motion。
