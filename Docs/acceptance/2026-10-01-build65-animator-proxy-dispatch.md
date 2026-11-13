# build65 动画代理派发修复候选

本轮保留原四个观察handles，poll确认仍live。安装保持61/主37272/状态流37273及37274，汽水37785。未安装候选、重启源、改变权限设置或做任何输入。隔离探针NSApplication使用prohibited activation policy，窗口从未order或可见；不是CUA输入，也不能替代屏幕实测。

## 发现与修复

候选64的final IslandPanel重写setFrame使用Swift直接派发；调用panel.animator().setFrame时可能直接在Objective-C代理上执行Swift重写并读取子类存储。独立同结构ProbePanel重现exit139/EXC_BAD_ACCESS，栈为swift_isUniquelyReferenced_nonNull_native→Array.append→ProbePanel.setFrame→NSAnimationContext group。崩溃发生在探针setFrame记录数组访问；候选产品是否在实机同样崩溃尚未安装验证，不能写成61的既有故障根因。

唯一派发变更为setFrame添加@objc dynamic，使消息通过Objective-C代理转发到真实窗口。相同探针不再崩溃并记录13个逐帧提交及完成回调。生产IslandPanel采用相同修复；新增IslandPanelAnimatorDispatchTests针对真实类的零时长animator调用，确认能够访问真实窗口状态、提交目标frame且窗口未显示。该测试防止代理调用路径回归，不证明非零时长动画。

未修正派发的探针源保留为.build/qa/appkit-frame-probe-direct-dispatch.swift，首次失败保留在本轮崩溃栈诊断记录，执行命令与首次失败记录在会话工具输出；可由Scripts/verify-appkit-frame-driver.swift移除@objc dynamic重现，但不在生产源码做此逆向试验。源探针初次编译因非main文件顶层表达式失败，改为@main后首次运行崩溃；不是生产编译失败。

## 隔离运行证据及界限

可复现驱动：`swiftc Sources/MacBookIsland/IslandAnimationFrame.swift Scripts/verify-appkit-frame-driver.swift -o /tmp/topislet-frame-driver`，运行时传一个不存在的JSON输出路径；加`--reverse`于80ms调度反向。探针拒绝覆盖已有证据，记录窗口几何而非用户数据。

`.build/qa/build64-isolated-appkit-frame-probe-dynamic.json`包含首轮成功的494个样本，completion约221.901ms、中间采样跨度176.438ms。请求240ms不等于观测到精确240ms；隐形窗口/采样起止定义不等于像素时长，不能称时长门禁通过。

`.build/qa/build65-isolated-reversal-{0..9}.json`及summary保存十次80ms调度反向，均最终200×32；提交frame顶边误差0、中心误差≤0.5pt，400ms后无非折叠frame写入。旧动画completion在取消后约80.892–88.524ms即触发，新完成约269.868–285.600ms；产品已有generation/currentMode门禁必须保留。隔离探针本身记录两回调，不代替生产gate测试。十次隐形反向不等于CUA实机反向10次，也不证明全屏orderOut、黑边、WindowServer或用户输入响应。

## 新候选

273项完整测试通过，控制安全/diff检查通过。Release ARM64构建17.65秒，独立DMG strict签名、版本65、布局、40初始化MachO段与当前Release二进制一致性校验通过。

候选：`.build/release-artifacts/build65/TopIslet-v0.1.3-arm64.dmg`，SHA256 `3584a0285076097fb39a8a8af1d2abf42a5906ec2f9bc3aa529ed5dfb49b71e0`。candidate-receipt.json安装/启动/真实动画/completion/中断/final字段均false。64保留历史，已被65替代，不安装已知风险的64。

原观察结束后先完整审核61性能证据、按现有回滚路径安装65，再验证实际时长/黑边/锚点/反向/全屏隐藏/所有控制与生命周期。65仍需自己的完整性能验收。Goal active，未推送、Tag、公证或发布。
