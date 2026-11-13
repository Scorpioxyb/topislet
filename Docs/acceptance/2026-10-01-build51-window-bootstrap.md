# build 51 窗口启动读取与前台三键

阶段 0 保持未完成。起始提交 c079cf7；本轮修改 MediaAdapter 的有限 AX 元数据重试，安装 0.1.3 (51)。

## 修改依据与范围

build 50 冷启动曾显示空岛，播放后才接管。代码中的启动元数据任务会在 windowClosed 时提前结束，而新 Electron 进程尚未创建窗口也可能返回零窗口。此条件是可能原因，并未用时序日志证明其为唯一原因。

- 启动有限重试不再因 windowClosed 提前结束，仍保持既有七次延迟上限、PID 与取消校验；权限缺失仍停止。
- AX 窗口结构通知同时触发有限元数据重试，使窗口重新出现时可读取歌曲。仅读取，不 reveal/activate，不添加持续元数据轮询。
- 全部 261 测试通过、汽水控制安全检查通过、Release 打包安装成功、codesign deep strict 通过、diff check 通过。

## build 51 实际验证

- 先 CUA Cmd+Q 退出汽水，独立进程表确认没有汽水主进程，再启动新安装版顶屿与汽水。
- 新汽水 PID 60480；未点击汽水播放、未手动刷新或调用状态 CLI，顶屿自动出现 golden hour (R3HAB Remix) / JVKE / R3HAB。展开有上一首、播放、下一首，时间未知使用 --:--。
- 点击顶屿播放后独立状态 isPlaying=true、elapsedTime=8.896287046569824、duration=154.76195。前台 com.soda.music、窗口未最小化。
- 下一首实际切 Copines (Techno Version) / Marla Malvins，duration=169.954717、elapsedTime=9.810532093048096。上一首实际回原歌，duration=154.76195、elapsedTime=7.810472011566162；每次独立检查前台仍是汽水。
- 暂停独立状态 false、elapsedTime=36.871574。汽水关闭按钮后两次间隔检查窗口数为 0，顶屿随后只显示明确的“重启并连接汽水音乐播放控制”入口，没有继续展示三个不可用按钮。没有点击恢复入口。
- 最后收起顶屿。CUA reset 后精确 TERM helper PID 60415，复查 SkyComputerUseService/CUALockScreenGuardian 均不存在。汽水进程保留、窗口关闭，顶屿运行。

## 尚未关闭的门槛与新增观察

修改前 build 50 暂停音乐后的下一轮，岛曾显示空岛；恢复汽水窗口后，岛 AX 曾短暂显示 golden hour 与 JVKE / R3HAB / Siren，而汽水窗口 AX 为另一首歌；独立新读取的 AX 与 MediaRemote 均为实际歌曲。说明旧读取或切换状态仍需排查，不能宣称 build 51 已修复此混合元数据现象。

本轮只证明一次暂停冷启动与前台三键；仍须重复冷启动、窗口恢复、后台三键回归、AX 异常恢复、Desktop 2/伪全屏、快速动画与黑边、点击区域、完整生命周期与最终 DMG。build 50 候选 DMG 不包含本轮修改，不能作为 build 51 最终产物。
