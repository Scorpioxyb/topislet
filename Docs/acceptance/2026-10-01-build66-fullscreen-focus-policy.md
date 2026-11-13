# build66 全屏抑制焦点豁免修复

本轮原四观察29621/99272/88032/7883逐一poll仍live；继续安装61/主37272，不安装候选、不重启或故障注入。未做UI输入、改变系统设置或权限。用户已禁止百度网盘测试，最终实机使用流媒体。上一轮为进展：回滚完整性/联合审核及第三次来源空读证据。

## 明确问题

代码存在`!frontmostIsTopIslet && hasCoveringWindow`豁免。检测器已排除本进程窗口；hasCoveringWindow=true因此表示其他进程覆盖目标显示器，但顶屿获得焦点后抑制仍变false。QA要求覆盖场景保持隐藏，不因媒体刷新/orderFrontRegardless恢复；该豁免使恢复显示条件成立，不符合要求。此为策略层已证明的反例，不冒称刚才在实机复现了用户旧故障。

先修改现有测试，让covered=true/frontmostIsTopIslet=true期待抑制。单独运行失败，/tmp/topislet-build66-fullscreen-red.log保留期望true/实际false。随后生产策略改为由hasCoveringWindow决定，前台身份不豁免。参数名保留调用兼容但不参与结果；没有增加播放器或改变窗口尺寸阈值/坐标/层级过滤。此方法只控制岛面板，不orderOut设置或校准窗口。

现有覆盖窗口筛选继续限定其他PID、layer0、onscreen=true、alpha>0.01，并用97%覆盖或保留菜单栏而覆盖Dock区域的几何规则。窗口处于其他显示器/未覆盖普通放大窗口的测试仍存在；自动隐藏Dock、原生全屏、独立伪全屏、Desktop2及实际窗口语义不能由这些几何测试完整证明，须最终安装候选实测。抑制调度仍为150ms+应用/Space通知；两处岛orderFrontRegardless都受isSuppressedByFullScreen保护。

## 候选

完整273测试、控制安全/diff检查通过。Release ARM64构建17.49秒，独立镜像strict签名、版本66、布局及40个初始化MachO段与当前Release二进制匹配通过。65动画@objc dynamic修复保留。

`.build/release-artifacts/build66/TopIslet-v0.1.3-arm64.dmg`，SHA256 `91312490e151d346f2bacaefaf50406633b1cf03b894120f7755d2e3984256dc`。candidate-receipt安装/启动/真实动画/completion/中断/全屏/final字段全false。66替代65为最新待安装候选，历史65/64保留，不重复覆盖已有镜像。

阶段0仍未通过。原两小时观察结束并完整审核后，保留已核实61回滚，从66最终只读镜像安装并实际验收焦点切换/隐藏退出恢复/三键/动画/生命周期；66自身长观察仍须完成。未推送、Tag、公证或发布。
