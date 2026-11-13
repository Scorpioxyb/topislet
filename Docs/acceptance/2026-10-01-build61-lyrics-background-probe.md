# build61 后台歌词核查与运行观察启动

安装版仍为0.1.3 build61，主37272、状态流37273/37274、汽水37785。实际CUA从紧凑卡片展开，点击播放，按钮变暂停；独立adapter-status确认verifiedQishuiSource=true/isPlaying=true、进度增加。同一汽水PID仍hidden=true/main minimized=1，没有唤起主窗口。

## 后台歌词试验

只读AX结构探测在最小化主窗口仍找到fullscreen-player、lyrics-view及paragraph active，但不能据此认为主窗口歌词正在追随当前播放。试验候选允许从最小化DOM读取歌曲身份/歌词集合、禁止使用其active段落，只把同歌曲已核实集合用于桌面歌词归属。独立编译候选读取60次/0.5秒全部rows=0。进一步诊断60次确认发现一个player，但titleMatch=false、artistMatch=false、artistCount=0；没有通过歌曲身份门禁。诊断只记录匹配布尔值/数量，不记录歌词正文、地址、设备标识或账户。

原始诊断：.build/qa/lyrics-minimized-diagnostic.log；探测候选和入口：.build/qa/lyric-probe/。当前可观察结论是最小化DOM身份与可信当前歌曲不匹配，不能据旧DOM显示歌词；不将所有汽水版本或全部最小化状态泛化为同样行为。放开最小化读取的试改已撤回，产品源码恢复HEAD，没有制作或安装build62。试改期间270项测试和控制安全检查通过；这不构成后台歌词实机成功。

现有歌词适配继续是：核对同PID、歌曲标题与完整歌手后读取主窗口唯一当前段落，支持原文/翻译至多两行；已有桌面歌词窗口只接受属于该歌曲已核实集合的行；不能核实则清空。后台任意新歌曲的完整歌词适配仍未通过。下一步需要找到能随播放更新且可验证歌曲归属的后台来源；不能以唤起主窗口或取消身份校验代替适配。

## 运行中的观察

资源观察session29621：swift Scripts/monitor-long-run.swift --pid 37272 --duration 7200 --interval 5 --output .build/qa/build61-long-run.json。

细子进程观察session99272：swift Scripts/observe-process-children.swift 37272 7200 0.1 .build/qa/build61-child-observation.json。

独立事件观察session88032：python3 .build/qa/build61-source-watch.py，白名单字段输出.build/qa/build61-source-playback.jsonl。按完整事件边界保存，尚无持久事件时不能作为播放成功证据。短时独立adapter-watch 3返回1个事件，不代表长观察已有效。

独立5秒播放采样session7883：python3 .build/qa/build61-source-samples.py，输出.build/qa/build61-source-samples.jsonl及完成后summary。启动晚于资源监测，最终只评价共同时间区间；不能声称两个完整两小时窗口重合。每次只读adapter-status会增加监测主进程之外的短寿命观察进程负载，事件观察也有独立状态流；不属于37272的直接子进程。记录只保留verifiedQishuiSource/isPlaying/elapsedTime/duration/sourceProcessIdentifier等白名单字段，不保存原始曲目/专辑/封面URL。

两小时观察尚未终结，不重启主进程、不注入源故障、不安装替换。资源门禁与细观察结果须分别审核，后者不能擦除前者的违规。播放采样只证明采样点，不证明间隔内播放或未锁屏。Goal保持active。

CUA已reset；对核实basename为SkyComputerUseService的PID37735执行TERM，最终另行复查两类helper。未改变权限、设置或外部数据，未推送、发布、公证。
