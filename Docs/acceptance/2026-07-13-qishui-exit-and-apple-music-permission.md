# 汽水退出清理与 Apple Music 权限验收

日期：2026-07-13

## 汽水音乐退出

- 顶屿监听 `com.soda.music` 的启动和终止通知。
- 汽水完整退出后，立即清除歌曲、歌手、封面、时长、进度、播放状态和待处理控制。
- 实机终止汽水后 0.8 秒截图确认顶屿回到折叠形态。
- 设置页确认旧歌曲已被替换为未运行占位状态，未继续显示退出前曲目。
- MediaRemote 会话失效后不再返回上一会话快照，迟到的位置差分不能恢复旧歌曲。

## Apple Music 实验适配

- 系统自动化弹窗确认请求方为“顶屿”，用户已允许控制“音乐”。
- 顶屿设置页显示 Apple Music 运行中、自动化权限已授权。
- Apple Music 仍为 `experimental`，汽水音乐仍是唯一 `active` 适配器。
- 尚未把 Apple Music 接入顶屿自动切换路由；当前阶段仅完成 PID 定向桥、权限和独立适配器基础。

## 自动验证

- `swift test`：42 项测试通过。
- `swift build -c release`：通过。
- `codesign --verify --deep --strict /Applications/顶屿.app`：通过。
- `Packaging/Info.plist` 与 `Packaging/TopIslet.entitlements`：`plutil` 校验通过。
- Computer Use 会话已重置，CUA 服务进程检查为空。
