# build 50 状态流退出与 DMG 内容校验

阶段 0 未完成。本轮没有发布或推送。

## 发现与修复

开始检查发现两个项目安装路径下的历史网易云 stream-client 进程 PID 12386、12445，PPID=1；当前顶屿 PID 49070 另有各一个网易云、汽水状态流。无法仅由现场断言历史残留的具体退出原因。

代码核实 MediaRemoteClientBridge 的 stop/restart 只调用 Process.terminate，随后清除引用，没有等待进程退出。现在两处复用既有 MediaRemoteAdapterStreamSource.terminateStreamProcess：TERM 后最多约 0.2 秒等待，未退出则 KILL，继续最多约 0.2 秒确认并回收。既有忽略 TERM 的真实 Perl 进程回归测试覆盖此共用收尾方法。历史两个 PID 经精确 TERM 后检查均已消失。

## 实机生命周期

- 完整 261 项测试通过，控制安全脚本与 diff 检查通过。
- Release 安装 build 50、签名验证通过；替换旧应用后 PID 49070 及旧两条状态流均消失。
- Computer Use 启动 build 50，主 PID 52554，网易云 52555、汽水 52556，均以 52554 为父进程。
- 精确向主进程发送 TERM，Python 从发送时以单调时钟计时、ps 每约 20ms 观察；三个进程全部消失用时约 0.147 秒，满足该轮一秒退出门槛。
- 再次通过 CUA 启动，最终主 PID 52628，网易云 52630、汽水 52631，均以 52628 为父进程，无 PPID=1 状态流。仅此一次 TERM 退出和重新启动，不代表正常菜单退出、SIGINT、重绑等全路径均完成验收。
- CUA reset，精确 TERM SkyComputerUseService PID 52529，复查该进程与 CUALockScreenGuardian 均不存在；顶屿保留正常运行。

## DMG 候选

本次检查 build-release.sh 后未执行其中 Finder osascript 布局步骤。使用当前打包应用生成独立内容候选 `.build/release-artifacts/build50/TopIslet-v0.1.3-build50-arm64-candidate.dmg`，无覆盖旧正式产物。顶层有顶屿.app、Applications -> /Applications，以及 LICENSE 和 THIRD_PARTY_NOTICES.md。

- hdiutil verify、只读挂载、包内 codesign --verify --deep --strict、CFBundleVersion=50、arm64 主程序及 Applications 目标检查通过。
- 包内主程序与 /Applications 安装版 SHA-256 相同：074b738fc89804d4bdc87ce19f2ad41c099d24f5a76bd00da60245cfd9c55e19。
- DMG SHA-256：9f42b7c314805784b5f3396c4c43f44cdca3a3b31b1c7dc7d3e5c228ba97cf13，对应 .sha256 校验成功。
- 镜像已正常卸载，临时 staging 目录按 move-to-trash.swift 移入废纸篓。
- 仅为本地 ad-hoc 签名内容候选，未验证安装界面布局/.DS_Store/背景图，不是正式发行通过；未公证、发布或替代最终 UI 安装验收。

剩余门槛包含当前 build 的三键与全屏回归、Desktop 2 与独立伪全屏、AX 异常、逐帧黑边及 80ms 反向、命中区域、全部生命周期路径和正式安装界面。Goal 保持 active。

## build 50 正常退出、SIGINT 和普通动画补充

- 从右键岛菜单实际点击“退出顶屿”，CUA 返回 App quit；独立检查主 PID 52628 与网易云/汽水 52630、52631 均不存在，安装路径下无遗留状态流。工具返回耗时约 5.5 秒，未独立计量该轮一秒退出门槛。
- 重启后主 PID 53295、子进程 53296/53297。向主进程精确发送 SIGINT，以单调时钟和约 20ms ps 观察确认三个进程全部消失，耗时约 0.120 秒。
- 再次通过 CUA 重启，主 PID 53483、子进程 53484/53485，父进程关系正确。
- `verify-island-window-animation.swift --observe-only` 20.0065 秒，2438 帧，平均 121.86Hz，始终一个窗口，屏幕中线误差 0.500pt、顶边漂移 0.000pt，尺寸 245×35 -> 420×211，未越过端点。CUA 实际展开和收起，未运行脚本 CGEvent 输入分支。
- 收起稳定态 CUA 截图未见圆角外矩形黑边。不是逐帧渲染证据，没有执行精确 80ms 反向十次。当前普通活动面板控制在新鲜 AX 树上可操作，不等于所有音乐按钮命中区域通过。
- 源码核对：展开内容在 model.mode 改变时即可出现在 AX 树中，窗口 frame 仍在动画；先前 elementHasNoFrame 有时序上的合理解释，但未经独立时间/命中测量，不能将所有相关失败归因为工具。
- CUA reset，精确 TERM SkyComputerUseService PID 53182，复查该进程与 CUALockScreenGuardian 均不存在。顶屿保持运行。
