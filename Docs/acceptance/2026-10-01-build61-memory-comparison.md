# build61 同进程中期内存比较

本轮对资源29621、细子进程99272、事件88032、5秒播放7883逐一poll，全部返回同一live session。安装61主37272和两stream37273/37274，汽水37785，没有重启或以新监测替代旧观察。

只读vmmap -summary在同一主进程上取得第二快照.build/qa/build61-vmmap-midrun-2.txt。与14:53:02快照（第二快照15:12:41，间隔约19分38秒）.build/qa/build61-vmmap-midrun.txt比较：physical footprint31.1→32.6MiB、peak79.7MiB不变；malloc bytes allocated13.4→14.0MiB、allocation count87210→87806；AttributeGraph主zone已分配205KiB、QuartzCore92KiB、AttributeGraph graph data41KiB基本不变。原始摘要及结构比较.build/qa/build61-vmmap-comparison.json保留。

这是同PID可比统计，确认中期增长；不证明内存泄漏、具体分配栈或封面缓存是根因。vmmap是外部只读观察负载，不替代每5秒资源门禁。源码解码封面缓存4项/总1MiB、原图缓存24项，当前缺少每项实际数据大小与malloc对象归属，未因猜测调整缓存。

约3435秒资源观察累计687样本，footprint增长42.8%、RSS下降8.8%、平均CPU约0.096%。之后观察继续，数值以终结文件为准。过程中的violations=[]不能当成功，因为结束时footprint/RSS增长门禁尚未执行。原baseline约23.97MB保持，不更换高基线。5秒播放662样本仅两次切歌附近unverified，其余trusted/playing，事件观察仍保留；不把这些采样扩成间隔内连续播放证明。

上一轮已形成build64本地候选，未安装。等待原61观察终结后，须分别审核资源/细子进程/播放证据；若footprint结束增长超过15%，按原门禁记录失败并继续定位，不能因动画候选已准备而跳过。随后安装64必须拥有自己的最终候选实机与完整长稳证据。Goal active，未推送/发布/改权限，未使用百度网盘或CUA输入。
