# build56 诊断分段与长时间监测启动

起始HEAD de460f3，安装56，主37264、汽水37785。未改产品逻辑。源码main.swift的--qishui-status明确先打印PRIMARY_MEDIA_SOURCE，再打印AX_FALLBACK_SOURCE；两个print函数都可以输出isPlaying。此前只rg同名字段丢失分段，因此true/false与unknown不能据此诊断为同一来源的矛盾状态。README补充分段解释，不修改或合并数据。

独立安装版命令保留分段输出，primary:verifiedQishuiSource=true、primary:isPlaying=true、primary:elapsedTime62.10530996322632、primary:sourceProcessIdentifier37785；ax:pid37785，本次没有AX isPlaying字段。不能把不同次输出推断为AX必定总是unknown。

锁屏环境一分钟只读ps采样正常结束：60.6484秒/60样本，ps CPU范围1.6至7.8%、RSS72144至73552KiB。ps CPU不是区间CPU增量，不将其与proc_taskinfo的区间CPU直接比较；一分钟与锁屏均不能替代正常使用的两小时门禁。

现有Scripts/monitor-long-run.swift已启动7200秒/5秒间隔，只读追踪精确核对的37264。活会话36300，日志/tmp/topislet-build56-long-run.log，汇总.build/qa/build56-long-run-locked.json与同脚本CSV。启动后同一会话轮询仍running，汇总20.096秒/5样本、processAlive=true、completed=false、平均区间CPU约0.111%、基线与当前子进程均2。这是早期记录，未完成且不能声明通过；后续继续同一会话，不因暂时无输出重启。

Finder视觉/安装、跨桌面与伪全屏、逐帧黑边/快速反向/全点击区仍待解锁后的实机验收。Goal保持active。本轮没有CUA操作，没有发送终止信号或更改系统设置，也没有发布推送。

## 监测进行中复核

同一36300会话再次轮询仍running；305.4905秒时62样本、processAlive=true、两子进程、连续CPU高于5%时间0、物理占用增长约0.4604%。violations当前为空尚未执行终态判定，不能据此算通过。核对实际CSV路径为`.build/qa/build56-long-run-locked.csv`，后来独立解析已有74行，包含时刻、elapsed、CPU、RSS、physical footprint、线程、子PID与窗口数。

CGSessionCopyCurrentDictionary仅输出screenLocked=true，未读取其余会话字段。新增临时只读session context观察器会话33348、日志/tmp/topislet-build56-session-context.log，以5秒间隔只记录锁屏布尔值变化与ISO时刻，读取监测summary的completedAt后退出（最长7200秒）。首次记录2026-10-01T17:08:23Z screenLocked=true；启动前时段只以已知锁屏观察限定，不编造完整历史。后续继续原监测及context会话，不重启、不改变系统设置；它们未完成。

后续同一36300会话50秒有界等待仍running。596.073秒时CSV120样本、elapsed严格递增、最大间隔5.028秒，窗口数全部1。子进程数不能声称全程2：2026-10-01T17:05:45.295Z、elapsed185.335秒样本有37266/37797/42983三个直接子进程，前后回到2。独立当前ps确认只有37266/37797两条stream-client，第三PID已退出，未捕获可执行路径不能确定用途，也不能仅据此判定泄漏；最终持续增长门禁仍待完成。锁屏context暂无解锁变化。本轮无产品修改。

提交前再次解析增长中的CSV，631.147秒又出现额外PID47292，前626.136秒与后636.159秒均为2。summary133样本时最大持续子增长5.0117秒、maxChildCount3、finalChildCount2、completed=false。不能把早期一个额外进程解释成全程只有一次；后续以完整原始数据为准。
