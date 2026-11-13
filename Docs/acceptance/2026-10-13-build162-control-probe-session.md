# 第三轮：build162 控制预检与媒体会话隔离

当前本地安装0.1.3 build162，第三轮goal仍active。无提交、推送或发布。

## 当前已证实的故障路径

build161在03:29:43.996记录 `source_unavailable reason=control_probe_instance had_direct=1 had_media=1`。后续岛同曲丢时长、显示默认播放标，源专属读仍有完整duration、playing=1、rate1、PID61388。控制预检回调按旧请求PID的一次 `NSRunningApplication(processIdentifier:)` 查找失败，直接调用 `markQishuiNotRunning`，清除所有歌词、位置、元数据并invalidate整个状态流。

这证明清会话的调用路径，未保存失败瞬间的AppKit应用清单，故尚不能判断当时是单PID查询暂态空、旧请求PID退出、新实例替换或其他平台问题。之后单独PID查询正常不能倒推当时原因；也不把此样本等同于build152旧来源缺失的根因。

## 修复

控制预检完成使用新鲜bundle限定应用清单：请求PID仍在则接纳；旧PID离开但其他汽水实例在则丢弃旧结果并重新绑定一次预检；只有清单确实为空才清会话。重绑复用已有in-flight与generation规则，不新增定时轮询。精确PID定位在单PID查询不可得时只允许同PID清单条目补位，不能以其他PID替代已绑定控制。仍保留源退出清理、过期快照拒收和唯一语义AX控件验证。

增加当前PID、替换PID、多实例和空清单策略回归，共359项Swift回归通过；控制安全、差异、Release打包安装及严格签名通过。此次策略新增直接测试新实现，并没有修改前行为红灯，不能称为实机故障全过程的失败回归。

包与安装二进制SHA256均 `2d8ecc5791c0ec78052e5cd11afb80f28120d49ad95e2ca871eb6b745a270907`。build161回滚位于 `.build/rollback/build161-before-probe-instance/顶屿.app`。

## 实机短窗口

安装后Sweet Release (Extended)展开显示暂停标、完整6:41时长和源歌词，两行分区无旧整卡重影。下一首到Lady Killers II，再上一首回原歌曲：

| 操作 | 接受 | 首候选 | 完整源 | 交付 | 模型发布 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 下一首 | 11ms | 89ms | 667ms | 679ms | 679ms |
| 上一首 | 14ms | 126ms | 685ms | 699ms | 700ms |

完整元数据到模型发布12/15ms；是两个样本，不是P95或物理键盘延迟。两次track_changed时长、封面、歌手完整且can_seek=1。最终专属源playing=1、rate1、duration401.070998、PID61388。汽水hidden=false、window minimized=false，与161安装前记录一致。没有重开、隐藏、取消最小化或重启汽水。

最终候选暂停/恢复尝试因CUA控件失效中断，没有发送新控制，不能算通过；日志仅有next/previous，最终播放仍在进行。build161四次控制样本为历史证据，不替代本候选。CUA出现native pipe关闭、窗口变化或控件过期时读取新状态，未以脚本/全局键绕过。

本轮短窗口未再记录source_unavailable，但不足以证明所有暂态实例故障或长时间运行通过。日志、源只读输出、窗口状态和构建证据 `.build/qa/build162-round3/`。build161换句修复及build160独立Safari窗口全屏隐藏/退出恢复见[上一份记录](2026-10-13-build161-lyric-compositing.md)。

## 剩余验收

- 本候选普通暂停/恢复、seek后暂停位置交接需补独立实机验证。
- 预检失效瞬间查找原因仍未捕获，修复策略有回归但长期不复发未证明。
- 跨Space尚未实际切换成功；当前单显示器无法做跨屏；物理键盘无精确按键起点。上述不计通过。
- 最小化AX不可读仍为上游限制，不自动改隐藏。
- 换句两张像素样本没有整卡叠影，完整逐帧视觉门禁仍缺证。

Goal不因359项测试和两次切歌样本而关闭。本轮未推送或发布，原dirty/untracked开发改动保留。
