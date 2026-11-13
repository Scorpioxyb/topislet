# 第三轮：build174 语义控件缓存顺序核验

## 缺口与修改

173两组快速切歌中捕获独立汽水源本身paused；这与172“无播放证据AX快照默认paused”的反证不同。当前只读控制诊断在PID61388发现1个合格底部控制组、345节点、标准主窗口未最小化；不能由这一时刻断言全过程节点从不变化。

控制器缓存路径仅检查窗口位置、唯一主窗口、节点enabled与AXPress能力，没有重读当前控制组内各节点的几何排序和身份绑定。renderer替换或换位时，旧next节点仍可按压并通过健康检查的合成场景可复现；没有实机节点变化证据证明它是173源暂停原因。

新行为复用缓存前只重读已缓存的控制组，沿用原3节点、左右尺寸和中间更大的几何约束，确认CFEqual节点身份按上一首/播放/下一首顺序一致。顺序或身份变化、读取失败均废弃复用并走原唯一候选重新发现；availability健康探测使用同一检查。PID和窗口/时长上下文等现有门禁保持，不加入新控制动作、窗口操作或周期扫描。

control_dispatch新增匿名dispatch_path=cached_verified/discovered/not_sent，以便实机区分当前操作路径。无节点文本、账户或歌词进入此字段。

旧健康策略抽取后新增2项回归，换位/替换/缺节点/无结果4断言失败；修复后17项控制相关回归、全套387项通过。失败和通过记录分别`.build/qa/build174-round3/cache-mapping-red.log`、`focused.log`、`full-tests.log`。合成回归证明策略结果，不是AX renderer真实换位证明。控制安全和diff检查通过。

## 安装与实机

已安装174，PID7701，Release40段一致与严格签名通过，安装/package SHA256均`9c0aec2030b47ffb6cbb29f4685f3d70a4ef10e5d77c829e4c12333f4b7ecb27`。

120秒三方采样2327条，1052展开；两组共8次next全部accepted。5次cached_verified的press耗时1–4ms，3次discovered为43/58/68ms，queue_wait均0。独立源19条全部当前汽水PID61388且playing，证明本次操作未抓到源paused，不能证明所有next都不会令源paused或语义顺序永久不变。

第二组后仍有5个paused展开样本，同时进度缺失，持续约246ms；07:34:46.847日志采用direct_match=1、media_match=0、无时长的AX备用快照。之后当前媒体duration缺失，约50ms恢复进度，保留172补齐路径实机证据。匿名日志及持续采样还记录07:35:09收回compact，输入归属未完整采集，不能判为故障或正常通过。

这再次反证173的0.8秒播放证据期限短于已有2.4秒切歌等待：超时发布时保护过期，未知AX仍能变成paused。174控件顺序修复是独立安全缺口，不视为暂停根因或稳定通过；175继续修复截止衔接。

证据`.build/qa/build174-round3/provenance/{summary.json,source-stream.jsonl,progress-samples.jsonl,live.log}`。两个观察自然exit0，日志Ctrl-C exit0。173回滚保存在`.build/rollback/build173-before-control-order-validation/顶屿.app`。不推送或发布；快速切歌源paused原因、完整歌词/键盘/资源门禁保持开放，第三轮goal未完成。
