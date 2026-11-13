# build65 隔离隐藏取消补验

本轮原29621/99272/88032/7883均poll确认live，不重开观察或替换安装61。承接上一轮实际派发修复（进展），新增隔离隐藏取消证据；Goal active。

Scripts/verify-appkit-frame-driver.swift新增--hide，与--reverse互斥；运行前拒绝缺少路径或覆盖已有文件。该路径在80ms调度中断后，按产品stopPanelFrameAnimation顺序清除target、零时长animator提交当前frame，再直接提交隐藏目标frame并orderOut。窗口初始未order、全程不可见，NSApplication activation policy为prohibited；未发输入、未启用CUA、未干扰汽水或岛状态。该探针不是全屏实机测试。

命令：`swiftc Sources/MacBookIsland/IslandAnimationFrame.swift Scripts/verify-appkit-frame-driver.swift -o .build/qa/appkit-frame-driver-hide`，每次执行传一个不存在的输出路径和--hide。本次十个输出为`.build/qa/build65-isolated-hide-{0..9}.json`，汇总`.build/qa/build65-isolated-hide-summary.json`。

十次实际中断调度落在80.816–87.613ms；原completion在中断后立即触发。中断后2ms起的4775个窗口frame样本均保持目标440×180，lateNonTargetWrites=0，结束均不可见，观察持续约1.04秒。2ms过滤仅排除中断同一次调用里的冻结frame，不修改或丢弃原始记录。产品已有generation/currentMode门禁继续需要，不能因为零时长替换就让旧completion释放新动画owner。

结论仅为：本机这个不可见隔离AppKit驱动的十次采样没有看到取消后旧frame覆盖直接提交的隐藏目标。仍不能证明可见窗口orderOut、全屏检测、底层点击、真实产品隐藏与显示恢复、像素黑边或精确240/180ms通过。候选65没有安装，receipt实机标志保持false。此次只更改诊断脚本，无生产二进制修改，因此仍沿用已校验65镜像，不重复生成同一构建号。
