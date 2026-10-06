# 顶屿开发更新：让音乐控制与歌词更容易看见

2026-10-06 · 本地开发预览 0.1.3 build 137

顶屿最初想做的事很简单：利用 MacBook 刘海周围的空间，让常用音乐操作和播放信息随手可见。这轮开发继续围绕这个目标调整布局，并把当前效果整理成了一段真实操作录屏。

![音乐控制与歌词动态预览](../assets/showcase/music-demo-build137-preview.webp)

[下载完整 30 秒演示视频](https://github.com/Scorpioxyb/topislet/raw/refs/heads/main/Docs/assets/recordings/TopIslet-build137-2026-10-06-github-16x9-muted.mp4)

## 这次画面里有什么

折叠时，岛保留歌曲信息和播放活动；展开后，封面、歌名、歌手与播放控制集中在左侧，把更多横向空间留给歌词。录屏包含暂停时的播放按钮、开始播放后的状态变化，以及当前句、下一句和歌词高亮。

![折叠音乐状态](../assets/screenshots/music-collapsed-build137.png)

![展开暂停状态](../assets/screenshots/music-expanded-paused-build137.png)

![展开歌词状态](../assets/screenshots/music-expanded-lyrics-build137.png)

这些图片从实际运行录屏截取。为适合 GitHub 阅读，视频外围重新设计了展示画幅；公开素材静音并模糊了第三方专辑封面。录屏中的歌词与界面来自当时的真实播放过程。

## 歌词还需要继续打磨

这一版已经能展示歌词随播放变化的效果，但短片不能代替完整验收。歌词读取延迟、逐字高亮的平滑度、长句显示、切歌后的归属一致性，以及播放器最小化或后台运行时的连续性，仍是后续重点。

我们也会继续检查折叠态是否影响系统菜单栏操作、悬停与固定展开的切换，以及全屏视频和不同桌面下的显示行为。目标是让音乐信息更容易看到，同时保持低打扰。

## 版本说明

| 内容 | 状态 |
| --- | --- |
| 公开可下载版本 | [v0.1.1-alpha.4](https://github.com/Scorpioxyb/topislet/releases/tag/v0.1.1-alpha.4)，Alpha 预览包 |
| 本文展示版本 | 本地 0.1.3 build 137，尚未公开发布对应代码和安装包 |
| 本次更新 | README 展示入口、视频包装、音乐状态截图和开发日志 |

这次没有新增 Release，也没有把开发预览描述为稳定版。后续会在歌词与控制、后台/全屏场景和打包检查完成后，再整理可下载候选版本。

## 想听听你的建议

你更常用折叠信息、播放控制，还是实时歌词？歌词的字号、显示行数和展开方式怎样更舒服？欢迎到 [GitHub Issues](https://github.com/Scorpioxyb/topislet/issues) 留下使用场景和建议；如果遇到问题，请附上 macOS 版本、播放器、顶屿版本，以及问题出现时播放器是在前台、后台还是最小化。
