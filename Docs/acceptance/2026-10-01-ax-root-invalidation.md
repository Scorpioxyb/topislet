# AX 内容根节点缓存清理检查点

阶段 0 未完成。起始 HEAD 26edeb0；已安装版本仍为 build 51，本轮源码修正尚未重新打包安装。

## 确认的代码问题

QishuiAXReader.invalidateCache 原本只清 cachedProfile，保留 preferredContentRoot。QishuiAdapter 在汽水退出、PID 改变与显式恢复时调用该方法；后续 readTrack 会优先读取 preferredContentRoot。因此显式失效操作未清理所有 AX 引用，旧进程/旧窗口根仍会被优先尝试。

本轮增加 preferredContentRoot=nil，使歌曲节点与内容根同时失效。不增加扫描次数上限、持续轮询、全局输入、窗口恢复或前台激活操作。

## 验证与限制

- swift test 全部 261 测试通过。
- 汽水控制安全检查、git diff --check 通过。
- swift build -c release -debug-info-format none 成功。
- 这个一行引用清理没有增加仅镜像实现的测试；已有测试不能证明真实 Electron 切歌与窗口恢复效果。
- CUA 尝试取得汽水窗口时返回 Mac 已锁屏、自动解锁失败。没有继续 UI 输入，没有绕过锁屏。
- CUA reset 后精确 TERM SkyComputerUseService PID 61290 和 CUALockScreenGuardian PID 61317，复查均不存在。

该缺口不是上轮混合歌手信息的已证实唯一原因。解锁后仍需检查同 PID 切歌、窗口重新创建、重复冷启动与完整元数据一致性；不能把本轮编译成功算作混合元数据实际修复。

本轮没有覆盖现有安装版或生成新 DMG。已安装 build 51 与新源码存在这一行差异，后续安装验收须明确区分。
