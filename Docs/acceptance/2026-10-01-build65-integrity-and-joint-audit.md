# 安装前完整性与长观察联合审核

本轮原29621/99272/88032/7883逐一poll仍live；没有重新启动或中止。上一轮属于进展：完成十次隔离隐藏取消取证。本轮取得当前回滚完整性证据，新增可复用终局审核并发现第三次来源空读。Goal active，未安装或发布。

## 安装前完整性

`.build/qa/build65-preinstall-integrity-20261001.json`：当前/Applications/顶屿.app仍为build61，与.build/rollback/build61/顶屿.app及原rollback-receipt的29个条目（含根目录）完全匹配。逐项检查文件SHA256及字节数、权限模式、目录和符号链接目标；两份strict/deep签名均通过。65候选镜像SHA256仍为3584a0285076097fb39a8a8af1d2abf42a5906ec2f9bc3aa529ed5dfb49b71e0，与receipt一致。只读核查不是实际执行回滚或启动证明。

## 联合审核

新增Scripts/audit-playback-observation.py，只读取指定前缀的资源CSV/JSON、细子进程终局JSON、源采样JSONL/终局JSON、事件终局JSON。调用：`python3 Scripts/audit-playback-observation.py .build/qa/build61 --source-pid 37785 --parent-pid 37272`。报告打印白名单统计，不打印曲目/歌词/URL；缺少或读到不完整数据时返回indeterminate，不控制进程或改写输入。

只有四份终局报告存在、目标PID一致、各时长达到原两小时、计数匹配、原资源门禁及共同区间/来源门禁全部满足才允许sampledEvidenceGatesSatisfied=true。末值RSS/footprint15%、CPU30秒、线程60秒、直接子进程30秒、单窗口和结束可见原门禁不变。原violations另外完整保留；细观察不能擦除粗资源违规。无论采样是否干净，continuousPlaybackAcceptanceProven保持false，因为报告本身不证明采样之间播放、解锁交互或事件接收时间精确重合。

当前真实未完成输入已运行核查：allFourReportsTerminal=false、sampledEvidenceGatesSatisfied=false，空violations没有被判成功。快照保存.build/qa/build61-joint-audit-interim.json；脚本的报告存在不证明handle仍live，必须继续poll原handle。

## 新空读

本次源采样未核实索引为291、323、986。986在observedSeconds4935.878799：前一采样elapsed132.290665/duration137.261678，后一采样elapsed4.870571/duration223.200998，同汽水PID37785、trusted=true/playing=true。空读本身exitCode0、mediaRemoteAvailable=false/verified=false且无isPlaying。时序与自然歌曲边界一致，但不能据邻居删除不确定性，也不能直接认为安装版主状态流失效。独立五秒CLI会增加短寿命观察负载，此局限持续保留。

最终安装前须继续等待四观察真正终结，调用同一脚本审核终局报告并保留失败证据。源采样起点晚126.266秒，不能把这次窗口描述成资源与播放共同完整两小时。候选65的自身资源/播放与屏幕操作门禁仍待安装后验证。

### 第四次来源空读补记

继续同四handle的50秒有界等待，均确认仍live；资源快照6115.769秒。新增索引1160/observedSeconds5807.386988，前样本elapsed290.510797/duration296.618685、后样本elapsed4.561445/duration87.561995，同PID37785且邻居trusted/playing。中间exitCode0但mediaRemoteAvailable=false/verified=false，无isPlaying。白名单邻居证据`.build/qa/build61-source-gap-1160-neighbors.json`。这再次与歌曲边界相符，但不删除空读或据此认定主状态流故障；当前未核实样本291/323/986/1160共4个，终局尚未完成。
