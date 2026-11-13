# build 53 内部全屏操作路径与候选包

阶段0未完成。本轮起始118f0e2，产品代码和安装版未变。

## 合成视频操作

Finder当前目录和180秒文件重新确认。右键菜单后重绑定仍导致菜单消失；换用顶部“文件 → 打开方式 → 百度网盘”成功打开视频窗口，AX标题“视频播放”、from=localFilePreview，后续明确显示topislet-fullscreen-180sec.mp4。

原生全屏按钮触发播放器全屏布局，之后通过窗口菜单“全屏幕”切回有关闭/最小化按钮的普通布局。视频播放结束后重新播放，正常布局右下角内部全屏图标实际可见。

CUA JPEG原始尺寸2160×1300，显示输出缩小为2048宽。初次按显示尺寸1204,1184点击位置偏移，未触发全屏；从JPEG SOF标记读取原始尺寸后，按原始坐标1270,1248点击内部按钮，AX移除标题/置顶/三色窗口按钮及底部控制节点，视频布局扩展。此证据证明内部入口操作已触发布局切换，不证明独立伪全屏类型。

操作后的独立检查frontmost=com.google.Chrome、hasCoveringWindow=false、islandOnScreen=1；百度AX当前windows=1、AXFullScreen=0对应普通主窗口，CG全窗口列表中视频窗口5620不在当前屏幕，bounds={X:0,Y:34,Width:1710,Height:1073}。后续前台变为com.tencent.xinWeChat。CUA视频窗口截图与当前桌面检测没有建立同一时间/桌面条件，不能据此判定顶屿隐藏通过或失败，也不能计入Desktop2验收。

最后清理操作前，绑定已切到“百度网盘”主窗口，脚本未先检查标题即通过窗口菜单执行关闭；该动作不能作为测试视频退出证据。后续UI动作必须在即时树确认标题为“视频播放”和合成文件后执行，发现目标改变就停止该动作。

CUA kernel reset，确认helper PID9309后TERM，复查SkyComputerUseService和CUALockScreenGuardian均不存在。

## build53候选DMG

候选位于`.build/release-artifacts/build53/TopIslet-v0.1.3-build53-arm64-candidate.dmg`，不是正式封版产物。从当前安装build53复制到临时目录，补入三份许可证并使用原项目entitlements和bundle identity重新adhoc签名，无安装覆盖或系统设置修改。

首次签名后直接比较可执行文件全部字节失败，原因是嵌入签名变化；在两份临时可执行副本中移除签名，逐字节一致。未对安装版移除签名。

- DMG SHA256：babad667018dca41a54a54343c9a510cae069dfe59075a5c159bf902122e7666
- 候选签名后binary SHA256：c2b647fda0f8f25fbbf51a8b5c3e1c9017ebbc253e86b70cb36388409b5fba63
- 去签名副本SHA256：bad1138e7528f11514ad09ce933cbcee597f1b5b30e05703d67d3120e239f2ca

只读挂载后独立核验DMG完整性/校验和、版本53、0.1.3、bundle identity、最低系统26.0、严格签名、arm64、候选binary hash、Applications链接和三份许可证均通过。正常卸载后验证挂载目录与生成临时目录均经move-to-trash.swift移入废纸篓；进程exit0。candidate-receipt.json记载readonlyContentVerified=true。

正式Finder布局、最终安装验收、公证及阶段0完整门槛未通过。不运行现有build-release.sh的AppleScript UI步骤，本轮全部UI通过CUA。
