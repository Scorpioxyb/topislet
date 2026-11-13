# build 49 原生播放器全屏验证

阶段 0 未完成。本轮无代码修改，仅补充当前安装版实际窗口证据。

使用既有 10 秒静音色条合成视频 topislet-fullscreen-test.mp4，通过 Finder 打开方式分别选择 QuickTime 和百度网盘；未打开私人视频。

- 开始时工作区干净，HEAD 381ce99，安装版 CFBundleVersion=49。
- QuickTime AX“切换全屏幕”由 off -> on；独立 `--fullscreen-status` 返回 hasCoveringWindow=true，WindowServer 在屏顶屿窗口数 0。
- 第一轮 Escape 退出，hasCoveringWindow=false，顶屿恢复一个窗口，245×35，X=732，Y=-1。
- 第二轮再次实际点击进入全屏。精确 TERM 顶屿 PID 45500，验证主进程消失；通过 CUA getApp 冷启动，工具等待可访问窗口超时。独立确认新 PID 49070 已运行、hasCoveringWindow=true、顶屿在屏窗口数 0。因此超时没有作为启动失败，也未重复启动。
- 第二轮退出后 QuickTime 又显示覆盖屏幕的打开对话框，窗口元数据为 x0/y34/1710×1073，检测仍为 true，岛保持隐藏。此时无法把旧 AX 全屏 off 标签当成恢复证明。打开对话框的来源未确定；第二轮退出恢复不计通过。
- 关闭测试 QuickTime 文稿/对话框后 detector=false。QuickTime 进程仍存在，不声称进程退出成功。
- 百度通过 Finder 打开合成视频，AX 顶部原生全屏按钮进入；hasCoveringWindow=true，顶屿在屏窗口数 0。Ctrl+Cmd+F 退出，hasCoveringWindow=false，顶屿在屏窗口数 1。
- 百度实际重新播放合成视频并截图确认色条；未独立完成播放器伪全屏入口，不能把原生入口算为伪全屏。
- 关闭合成视频窗口保留百度主应用；CUA reset，精确 TERM SkyComputerUseService PID 48566，复查 SkyComputerUseService 与 CUALockScreenGuardian 均不存在。最终 detector=false，顶屿在屏窗口数 1，主 PID 49070。

本轮补齐当前 build 49 的 QuickTime/百度原生全屏单次往返及 QuickTime 全屏内顶屿冷启动隐藏。没有实证 Desktop 2、独立伪全屏、全屏期间歌曲刷新，以及恢复原音乐/活动内容；其余音乐、动画、命中区、生命周期、DMG 门槛继续保留。
