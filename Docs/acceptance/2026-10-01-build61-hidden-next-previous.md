# build61 一小时观察中的隐藏后台切歌往返

原观察资源29621/细子进程99272/事件88032/5秒播放7883逐一poll确认仍live，安装61/主37272/stream37273及37274/汽水37785。源码候选64仅审查取消逻辑，本轮未改动或替换安装。保持播放，未进行暂停、退出、重启或故障注入。

初始曲目接近歌末，展开前自然切歌；.build/qa/build61-hidden-control-before.json不能当下一首操作基线。展开后重新独立adapter-status记录before-next：trusted/playing/PID37785、elapsed19.252/duration214。CUA读取最新完整树后点击topislet.music.next。独立after-next确认可信、播放、歌曲指纹不同、elapsed16.009/duration188.913；基线距离曲末足够，不把自然到歌末混成操作成功。

随后CUA新鲜完整树点击topislet.music.previous。独立after-previous可信/playing/PID37785、elapsed13.399/duration214、歌曲指纹准确回到before-next。最终CUA树显示原曲/歌手/进度0:26/3:34及暂停按钮、上一首/下一首均存在。保存的原始独立状态JSON仅白名单字段+歌曲SHA256指纹，不含原文歌词、专辑、URL或账户标识。汇总.build/qa/build61-hidden-next-previous-summary.json。

两项操作前后只读窗口形态汽水同PID hidden=true/main minimized=1/desktop minimized=0，前台均Safari。仅前后快照，不宣称整个操作窗口的激活事件数或鼠标位移已经连续测量。命令后立即CUA树仍显示旧曲，后续已追随权威状态，未测精确延迟。播放/暂停往返不在本轮执行，以保持观察中音乐播放；旧61播放开始成功与本次两项切歌不能合称所有背景/前台/异常状态的三键完整验收。

资源继续至约3816秒/763样本，footprint原基线增长43.1%，观察未终结；独立5秒播放738样本仍只有此前两次自然切歌空读，最后trusted/playing。此次手动切歌已纳入长稳操作记录，不把所有切歌称自然播放；未重新起监测，不更改资源阈值/基线。

CUA reset；精确核实basename后TERM SkyComputerUseService69215与CUALockScreenGuardian69279；首次复查有重新出现的SkyComputerUseService71464，继续精确TERM后最终复查两类helper无残留。源持续播放未激活。Goal active，本次61控制证据不能自动覆盖64的最终验收。
