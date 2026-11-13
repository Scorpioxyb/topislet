# build 52 安装与两轮恢复实测

阶段 0 未完成。本轮无源码修改，起始 HEAD 20c78fc。锁屏限制已解除，CUA 可实际读取与操作窗口。

- 精确 TERM 旧顶屿 PID 60450。只读挂载 build52 候选 DMG，校验主程序哈希后将旧 /Applications/顶屿.app 移入 Trash，再 ditto 安装镜像内部应用，codesign deep strict 通过，卸载镜像。
- 安装版本 52，主程序 SHA256 39dd379b52bb9e4c5f3c6b82e144e85a645fa7ccb29396dcebb77e8de856888a，与候选一致。CUA 启动成功。
- 初始汽水窗口关闭，顶屿显示原歌曲及明确重启连接入口；未显示三个可用控制。
- 第一轮用户入口恢复，汽水新 PID 91610：旧歌曲清空，未先按汽水播放、未手动刷新或调用状态 CLI，顶屿自动显示 Copines (Techno Version) / Marla Malvins，三个按钮可用，播放键、未知进度 --:--。
- 从顶屿播放后 AX 与独立 MediaRemote 当前歌曲一致，isPlaying=true、elapsedTime=12.35536003112793、duration=169.954717。
- 下一首切 Neeks / KaKashi，独立两源歌曲一致，duration=143.937574、elapsedTime=28.936041831970215。完整岛 AX 随后显示同歌。上一首回 Copines，两源歌曲一致，elapsedTime=9.396102905273438。操作后的即时 AX 仍旧歌曲，未据此声称完整切换已完成；后续状态确认实际完成。
- 播放中点击汽水原生关闭，两次间隔只读检查均 windowCount=0、PID仍91610；岛保留进度并呈现恢复入口。没有自动弹出窗口。
- 第二轮点击恢复后旧歌清空，新 PID92624，自动显示 Neeks / KaKashi、播放键与 --:--，未继承上个进程播放进度。点击岛播放后独立两源歌曲一致、isPlaying=true、elapsedTime=9.304404735565186。
- 最后岛暂停，独立 isPlaying=false、elapsedTime=36.586685；收起岛，汽水窗口保留。
- CUA reset 后精确 TERM helper PID91250；复查 SkyComputerUseService/CUALockScreenGuardian 均不存在。

这两轮恢复及一次 next/previous 往返检查点未出现混合歌手信息；没有连续采样所有中间状态，不能据此宣称完全消除跨歌曲混合或长时间稳定性通过。

build52 安装运行门槛已补实证，但后台三键、AX 异常恢复、Desktop2/伪全屏及其他播放器回归、快速折叠/逐帧黑边/命中区、最终生命周期与 Finder 安装布局门槛仍保留。候选 DMG 不因此变为最终稳定版。
