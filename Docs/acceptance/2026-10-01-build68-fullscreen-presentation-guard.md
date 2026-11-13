# build68 显示前全屏状态复核候选

当前实际安装仍为67，主12546、状态流12550/12551、汽水37785。68未安装，不能把候选检查迁为67运行结果。

## 问题与修改

67原生Vimeo进入覆盖窗口的头103.693ms仍有岛样本；源码定时检测150ms，与轮询等待相符但未证明唯一原因。另有确定的陈旧状态路径：repositionPanel动画开始和updatePanelVisibility直接使用上次isSuppressedByFullScreen决定orderFrontRegardless，媒体或布局刷新可能早于下一轮检测。

68把查询/更新抑制状态与显示动作分开；布局动画准备显示前、updatePanelVisibility准备显示前重新检查覆盖窗口。保留原屏幕选择、检测规则、隐藏取消和150ms定时回退。没有权限修改、跨应用输入、来源激活或新增AX观察。

该修复针对刷新时使用旧状态重新显示的路径，不证明进入全屏零延迟，也不是104ms初始延迟已修复。增加的CGWindow查询开销需要当前候选自身性能验证，不以提高常驻轮询掩盖。

## 探针边界

只读Safari AX事件探针注册应用及当前窗口的6类通知，12次注册成功。首40秒88事件、第二40秒229事件，含Moved/Destroyed/FocusedWindowChanged；两轮期间浏览器活动标签在调用间切到其他页面，播放器索引两次失效。没有有效完整全屏输入序列，不能将事件当作全屏快速通知证据。未添加生产事件观察，保留原始build67-fullscreen-ax-events*.json，内容仅通知名、时间、注册结果，不保存页面正文或输入内容。

为避免影响当前窗口使用，停止UI操作；本任务新建Vimeo测试标签尚未确认关闭，不操作其他标签。CUA reset后两类helper均无残留。

## 验证及交付状态

274测试通过；控制安全检查、diff检查通过。Release22.85秒；最终只读镜像独立签名、版本、布局及参考Release二进制初始化MachO段匹配校验通过。候选DMG SHA256 c67640d87297f7e866cf80ac254ca5119f1e5b8bc9ba2a97cf165a10ff554ee6。

证据：/tmp/topislet-fullscreen-presentation-guard-tests.log、/tmp/topislet-build68-release.log、/tmp/topislet-build68-dmg-verification.log。68未安装/实机验收；67全屏早期样本仍保留，Desktop2、独立伪全屏、关闭窗口、黑边、异常矩阵、性能及歌词门禁继续开放。Goal active，未推送发布。
