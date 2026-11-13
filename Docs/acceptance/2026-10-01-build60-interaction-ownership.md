# build60 直接点击接管悬停展开

源码发现：hover进入后didExpandFromHover=true；展开面板内直接播放/切歌及重复请求expanded不会改变mode，因此mode观察器不清除悬停任务。鼠标随后移出仍可由旧350ms任务收回。这是可以解释既有收回反馈的一条代码路径，不将它说成全部离屏错误的唯一原因。

本次将交互意图与mode变化独立：用户请求状态、直接控制动作发布presentationInteraction；AppDelegate取消进入/退出任务、作废hoverGeneration并清除返回态。实际面板左键按下只在已展开且有效交互区域内接管，设置音乐为用户固定展开；透明边角不接管。outside点击收回、显式收起与纯hover移出仍保留原规则。不更改媒体控制发送路径。

swift test全部270项通过；控制安全检查和diff通过。build60完整Release/DMG脚本成功；独立镜像签名与40代码/数据段比对通过。DMG .build/release-artifacts/build60/TopIslet-v0.1.3-arm64.dmg，SHA256 b8263487e3188445ae2cad4e99c1a71945fc4dcb27694f652304e7bdfb33b58e。

先将安装59完整备份到.build/rollback/build59/顶屿.app，28条内容/模式/链接一致、签名通过。59主6687与stream6690/6691在SIGTERM后114.392ms内消失，汽水37785保持。旧安装59移Trash；从只读挂载的最终60 DMG安装，安装二进制与镜像字节一致，SHA256 6b31080336cbe15ba70b646c5f5957103f6dc0e0ba66b709123438c2bd51c1f5。

CUA启动实际安装60，PID18925、两stream18928/18929；展开后三键出现，实际播放可信主源true、原汽水37785；实际暂停后可信false、Direct With It52.723132秒。卡片截图显示原文/翻译，控制保持展开。本轮未完成指针移出或严格hover→点击→移出的渲染序列，不将基础点击成功当作该完整门禁通过；本工具没有文档化move API，不通过其他技术合成输入来替代。

CUA reset、TERM精确helper18890，ps确认两种服务无残留。60已安装/启动/基本播放暂停，最终验收false；59异常恢复/关闭/fullscreen证据保留但不自动升级到60。下一项必须补hover移出与outside点击、60控制及全屏回归、动画黑边/命中区、生命周期/活动还原与当前版本长稳。未推送、公证或发布，Goal active。
