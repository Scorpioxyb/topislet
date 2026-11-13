# 第三轮：build176 外部点击位置快照

用户补充自然切歌后收起时“应该是点击”。该样本保留外部点击解释，不认定为自动收起故障。代码检查另外发现event tap将收起任务排到MainActor后才读取当前鼠标位置；点击位置与随后指针位置可能不同，这是一条独立误判风险，未证明是用户该次收起的原因。

现在event tap同步捕获事件的WindowServer坐标，使用主显示器高度转为AppKit坐标，再传给异步任务；global monitor优先使用同一事件坐标，缺cgEvent时只在回调当下取一次位置。去掉异步阶段的参数空缺入口。保留展开模式、可见性、自动收起设置、校准/设置窗口避让和既有命中区规则，不新增监听器、不修改用户设置、不改变汽水窗口状态。

3项回归覆盖岛内点击后移出、岛外点击后移入，以及左侧/上方副屏坐标；全套391项通过，控制安全脚本和diff检查通过。测试验证捕获坐标的归属及转换，未冒称真实多屏操作或可控主线程拥塞验收。

Release/package安装退出0、40段一致、严格签名通过；源码/安装版本0.1.3 build176。安装与package二进制SHA256均为`4720b2aa8d06bd4c4a336f1b30e0493f1a798d8e8501109e2a1358124e27b296`。安装后PID18329。回滚保留在`.build/rollback/build175-before-click-location/顶屿.app`。

安装后通过实际CUA点击从折叠到紧凑，再到展开，AX/截图都有当前曲目、歌词、暂停按钮和播放进度；面板内非控制区点击后仍展开，歌词与进度继续更新。汽水仍PID61388、hidden=false、minimized=false，收尾独立get-client确认PID61388、playing=1、rate=1、elapsedTimeNow=209.089秒、duration=237.183秒。工具没有精确move接口，不声称已在实机重现点击后立即移出与异步拥塞竞态；物理外部点击完整序列仍待核验。

build175短采样与未通过项见[上一记录](2026-10-13-build175-evidence-deadline.md)：四连切歌无假暂停的短窗证据与一次进度缺失同时保留；源明确paused和往返后的暂停根因未判定。build176没有改变音乐读取/选择政策，不迁移旧版门禁为本版通过。第三轮goal仍active，未commit、push、tag或发布。

收尾CUA会话已reset，仅按完整可执行路径退出专属SkyComputerUseService；进程检查确认SkyComputerUseService与CUALockScreenGuardian均不存在。两段诊断观察及日志stream均退出0。未关闭或重启Codex/app-server/任务宿主。
