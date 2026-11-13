# build61 原始动画失败证据与build62候选

当前安装仍0.1.3 build61/37272，binary SHA256 a4ba9fa3f9811e1dd95bfd2deb585b2e11c18247809731ee435eb9a6e4edf860。运行中的资源29621、细子进程99272、事件88032、5秒播放采样7883均保留，未重启、停止源或替换安装。前一轮为进展，本轮首先逐一轮询同一handle确认live。

## 流媒体窗口观察

使用已有Safari Vimeo Big Buck Bunny静音视频。调度中心ctrl+Up与getApp(com.apple.exposelauncher)未取得桌面编号，不能算Desktop2通过。Safari前台交互需通过Finder定位/打开现有Safari；没有激活汽水。

观察session38659正常终结，.build/qa/build61-vimeo-music-120s.json：120.0687秒/1132样本，初始Safari缩略窗口292x340，随后另一个Safari layer0 alpha1覆盖窗口1710x1074位于(0,33)，1000样本顶屿0。样本前台全部Chrome，不能称原生全屏前台播放验收。独立AX后来显示覆盖窗口为无标题AXDialog/AXFullScreen=0，原视频窗口854x991且WindowServer縮略。视频进度06:55至07:56，后自然结束，截图仍有浏览器工具栏；因此限定为本次Safari覆盖窗口触发隐藏，不冒称原生/独立伪全屏或Desktop2全部通过。Escape多次未清理覆盖，不计退出成功；CUA点击本任务视频窗口关闭按钮后返回Safari起始页，独立岛窗口恢复1/460x191，汽水同PID hidden=true/min1继续播放。

## 原始动画采样

verify-island-window-animation.swift --observe-only新增可选--samples-output，拒绝覆盖、只存uptime/elapsed/window frame/count，在几何验证前写出以保留失败数据。默认合成输入模式未运行。

session23250正常终结exit1；.build/qa/build61-passive-animation-raw.csv含8669样本但仅展开态，没有动作落入20秒窗口，不能判通过或产品故障。

session38776正常终结exit1；CUA展开/收起动作落入第二窗口，.build/qa/build61-passive-animation-raw-2.csv与对应-summary.json：19.997秒/8778样本/438.97Hz/maxGap32.295ms，单窗口/中心0.5pt；44样本Y=-2而稳定Y=-1，顶边漂移1pt，几何门禁失败。两个展开中间帧跨度466.219/465.823ms，两个收回566.370/566.164ms，明显超过目标240/180ms。没有同步输入时间戳，跨度是窗口元数据的中间帧至终点，不是精确渲染时长；仍足以反证本次动画已满足目标。没有执行80ms反向10次，没有逐帧画面黑边证明。较早20秒通过汇总不足以推翻此次原始失败记录。

## 修正候选

SDK NSWindow.h明确setFrame:display:animate:的总时长由animationResizeTime:决定；现用panel.animator().setFrame与resize后setFrameOrigin修正，context.duration的源码值并未证明实机总时长。精确机制仍不能只凭头文件断言，但实际尺寸延迟/顶边漂移已证实。

build62改为NSWindow.displayLink(target:selector:)显示同步回调推进单条时间轴，使用CACurrentMediaTime/targetTimestamp；每帧先整点取整宽高再由目标中心/顶边构造frame，直接setFrame而非AppKit默认窗口动画及resize通知后的origin修正。终点/反向、显示拓扑变化、减少动态效果、退出均停止并invalidate旧link，旧link身份/animationID/mode检查防止迟到回调；完成前claimCompletion。窗口与SwiftUI共用同一组cubic曲线及240/180ms值。反向从panel实际当前size开始。

新增IslandFrameTransitionTests覆盖展开/紧凑/折叠每毫秒锚点与边界、240/180ms期限、80ms反向接续、即时/迟到帧；最终274项全部通过，控制安全及diff通过。单元测试不证明显示器实机渲染或新显示link生命周期，后续必须安装验收。

ARM64 Release16.39秒完成；候选.build/release-artifacts/build62/TopIslet-v0.1.3-arm64.dmg，SHA256 ed0fb3b1528c0cc6d9792e3e1a046a6d2b77c79d895874cdd6d8f585e021b5bf。独立verify-release-dmg.sh BUILD_NUMBER62/REFERENCE_BINARY实际SwiftPM .build/out/Products/Release/MacBookIsland：strict签名及40初始化代码/数据段一致通过，文件/布局/版本校验通过。未安装、未称修复实机通过、未推送或发布。

## 持续观察限制与歌词

约2118秒资源观察仍live/no violations；细观察暂时第三子进程出现，增长跨度约0.212秒，不能在终结前称长稳通过。独立5秒播放采样1456.278/1616.420秒出现mediaRemoteAvailable=false/verified=false，无isPlaying；前后5秒均trusted/playing、前样本接近歌末后样本新duration/elapsed，独立事件流已保存28事件全部trusted/playing。合理推断与自然切歌有关，但不是已证明全程连续播放；保留空读，评估共同窗口和观测负载，不替换资源门禁结论。

后台歌词仍未完成。只读限定LunaStorage目录统计5条/队列文件1条；对唯一queue类别文件进行有界解压和仅schema计数，5000节点上限内未找到lyrics/content，根5个子对象的已识别键仅playables。到达遍历上限不能推断全部缓存不存在歌词；无正文/路径/账号/地址输出。生产没有重新开启缓存轮询，不扩展到无关缓存。

CUA reset后TERM精确SkyComputerUseService43311，复查两类helper均无残留。Goal active；等待61原观察终结后保留完整回滚，再安装62从最终DMG验收窗口时间轴/几何/80ms反向/显示link停止及其他当前版本门禁。
