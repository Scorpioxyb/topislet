# build67 原生流媒体全屏与AX无响应恢复

安装版主12546、两状态流12550/12551、汽水37785，未重启或替换。只使用Vimeo流媒体，未使用百度网盘。

## 原生全屏

CUA在Safari新测试标签打开公开Vimeo播放器76979871，实际播放、点击播放器全屏，AX窗口AXFullScreen=true。播放器时间推进、全屏内暂停及恢复播放操作成功；源汽水仍可信playing、hidden/minimized、同PID。截图未见顶屿，但截图是应用窗口范围，不单独当全桌面无遮挡证据。

独立CGWindow采样的前两次统计存在不足，保留原始数据：首次用英文拥有者名未匹配；第二次按bundle发现PID，但用面积97%阈值，与产品宽高/菜单栏规则不同。没有将错误统计当通过。

第三次保留Safari实际边界，1366样本/35秒；显示1710×1107、菜单栏34pt，全屏主体(0,34,1710,1073)。按当前产品coversDisplay或coversPlayerDisplay核验747个覆盖样本，共18.634秒。进入早期2样本仍有岛，最后一次在首覆盖后103.693ms；首覆盖300ms后没有非零岛样本。无锁屏样本。保留早期出现，不称全程无闪现通过。AXFullScreen true证明原生全屏窗口，但没有取得调度中心空间编号，不声称独立伪全屏或Desktop2通过。

退出后AXFullScreen=false、产品hasCoveringWindow=false；CUA看到原展开音乐卡片、同主PID和三键恢复。调度中心快捷键后获取Dock超时，Escape返回，桌面编号仍未证实。未更改桌面布局或系统设置。

证据：.build/qa/build67-vimeo-fullscreen-{samples.json,corrected-samples.json,bounds-samples.json,bounds-summary.json,ax.json}、build67-vimeo-after-fullscreen-ax.json、build67-vimeo-fullscreen-source*.json。观察脚本build67-fullscreen-observe.swift只读窗口元数据、不保存窗口标题。

## AX无响应与恢复

核实37785确为/Applications/汽水音乐.app/Contents/MacOS/汽水音乐后，用独立Python进程SIGSTOP25秒，finally发送SIGCONT保障恢复；停止1790899087.857174，恢复1790899112.861912。ps确认期间状态T。测试时无长观察进行，不污染两小时性能证据。

期间CUA读到“正在确认汽水播放控件是否可用。”及“重启并连接汽水音乐播放控制”入口；未点击该入口或改变权限。恢复后无需用户同步、无需重启，三个语义按钮自动返回。实际暂停/播放UI转换成功，独立adapter确认同歌曲false/true，源仍37785、hidden/minimized、前台快照Safari。

只确认此25秒无响应场景和恢复后暂停/播放；未测恢复时间上限、权限变化、持续异常、控制请求挂起/取消及恢复后上一首/下一首。恢复入口在确认阶段出现的文案与显示时机仍需产品评估，不能据此宣称所有反馈完善。

证据：.build/qa/build67-source-suspension.json、build67-controls-after-ax-resume.json、build67-controls-ax-recovered-{pause,play}.json。Goal仍active，封版尚未完成。
