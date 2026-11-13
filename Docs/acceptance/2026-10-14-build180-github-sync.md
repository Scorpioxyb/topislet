# build180 GitHub源码同步

2026-10-14，用户授权“可推送 github”。此次范围是源码与公开文档同步，不创建新Release。

远端为`Scorpioxyb/topislet`，目标`main`。从远端`15cf4bd`创建独立托管worktree，保留主工作目录及已有另一脏worktree；按当前build180整理源码、测试和版本号，并更新公开README、CHANGELOG、ROADMAP及开发更新。没有上传内部验收文件、原始录屏、设计中间文件、个人路径或诊断日志；已公开素材保留。

41个文件，3134行增加、522行删除。提交`9efccd8f7e58e6208a5bba8efc7446dfc0c09e53`已通过普通fast-forward推送到GitHub main，并由ls-remote和GitHub API核验。没有强推、重置主工作目录、创建tag或Release。

独立候选与主工作目录Sources/Tests逐文件比较一致；395项回归通过（2.414秒），Release编译通过（23.61秒），控制安全及暂存差异检查通过。源代码和安装版仍0.1.3 build180。旧下载包v0.1.3-alpha.1/build148保留；演示素材仍build137，README明确区分三者。

## 云端CI失败，不能视为发布门禁通过

[CI运行38530086669](https://github.com/Scorpioxyb/topislet/actions/runs/38530086669)已终止为failure。仓库检查、Debug编译通过；395项测试中只有`sessionInvalidationCancelsExhaustedDeferredWait`在`MediaRemoteAdapterStreamSourceTests.swift:1959`失败，断言为`await waitUntil(timeout: 1) { reader.readCount == 6 }`。运行记录显示测试约1.088秒超时。Release构建与打包步骤因此未执行，不能以本地编译结果替代。

已按gh-fix-ci技能进行只读检查，该技能要求先确认方案再实施。拟将这组耗尽补读测试改为明确等待实际进入耗尽后的等待阶段，再注入来源失效/完整状态流；保留最多6次读取、取消后不回写旧候选等业务断言，不通过跳过测试或单纯扩大超时掩盖故障。具体测试同步与生产调度原因尚待验证，不把一次CI等待超时解释为已证实的应用故障。

独立worktree`~/.codex/worktrees/build180-source-sync/MACBook 灵动岛`保持干净并附着，分支`codex/build180-source-sync`，以便获准后修复。未实施额外CI修复或再次推送。原始日志保留在该worktree的`.build/publish-check`。

## 获准后的CI修复与最终结果

用户回复“同意”后实施。只修改`MediaRemoteAdapterStreamSourceTests.swift`与两份公开说明，未修改Sources、应用版本号、CI工作流或任何生产超时/预算/身份门禁。

先给取消测试加入慢读取参数：每次220ms，原一秒断言确定失败，保留`.build/ci-phase-fix/red-delayed.log`。读取计数在每次调用入口增加，不能代表最后一次响应完成。修复将三项耗尽测试改为等待已有DEBUG只读标记`deferredPublicationIsPassiveForTesting`，阶段等待保留2秒测试安全上限；移除固定30ms睡眠，显式要求在途等待任务存在，再注入取消或完整状态流，保留6次读取上限与旧曲目不回写断言。没有通过跳过测试或放宽生产2.4秒发布期限取绿。

聚焦3测试（取消测试含即时/慢读取两个参数）通过；随后一次全套395项回归通过（2.530秒）。修复提交`bcb74a9f8560728c8369c7682018c267954c105d`已普通推送至GitHub main，ls-remote确认一致；修复候选worktree保持干净，测试与公开更新已同步回主工作目录。

[CI运行38531224954](https://github.com/Scorpioxyb/topislet/actions/runs/38531224954)最终completed/success。云端395项测试通过（2.867秒），取消测试两参数通过；Debug、Release、39段二进制一致性、DMG检查及产物上传全部通过。首次失败运行仍保留为历史反证，不重写为成功。最终日志保存在独立worktree`.build/ci-phase-fix/ci-final.log`。

此修复只关闭该测试同步失败，不关闭应用快速切歌、后台歌词、物理键盘及长期运行等旧实机门禁。未重新安装应用、未操作汽水、未创建tag或Release；公开下载仍build148，安装版仍build180。托管worktree保留供后续源码同步复用，没有删除任何用户文件。
