# build68 安装、后台控制、菜单生命周期与静态截图

2026-10-01 17:09:48 -0700从最终只读镜像安装68。镜像SHA256 c67640d87297f7e866cf80ac254ca5119f1e5b8bc9ba2a97cf165a10ff554ee6；29项内容/权限/符号链接全部匹配，strict签名通过。安装binary SHA256 19223c6d198509bf4b80e01979911b19f15efa9bc2f2f9e4dceb271031291e78。

安装前build67回滚副本.build/rollback/build67/顶屿.app的29项与当时安装一致，strict签名和binary hash核实；对旧12546发SIGTERM后12546/12550/12551全部消失，汽水37785保持。旧安装移Trash，未永久删除。CUA启动68初始25936/25958/25959。

## 实际后台控制

暂停与恢复UI按钮转换，独立白名单快照确认同曲目false/true。之后菜单退出并重开，再进行下一首/上一首：曲目指纹改变后准确回到原指纹。每个源状态快照仍37785、hidden=true、mainMinimized=true、前台Safari。此为实际动作及前后快照，不证明全过程指针/前台保持、延迟或其他媒体不受影响。

关闭窗口测试未完成：CUA选到桌面歌词，窗口菜单超时，当前Mac CUA没有launch_app接口。未使用非CUA输入强行还原，不把读取不到主窗口当“主窗口关闭”或通过。后续读取过滤桌面歌词HTML URL及配置字段，不将其写入QA。

## 菜单退出及重开

实际右键岛→退出顶屿；CUA随后noWindowsAvailable。并行只读ps观察310点，最后仅主25936存活后约30.245ms的下一样本三PID均消失；观察起点与点击未同步，不能声称退出延迟30ms或满足精确时限。汽水37785保持原进程。CUA重新启动68，新28073、两流28074/28075；再次查询同App未产生重复进程，但不把getApp查询等同于第二次启动请求。单实例启动竞态仍须单独验收。

## 静态窗口截图与锁屏

锁屏前取得窗口ID10831的真实展开截图.build/qa/build68-expanded-window.png，920×382像素。Screen Recording已授权，未申请新权限。alpha检查46456个透明像素、304288个完全不透明像素、696个部分透明像素，四角alpha=0。白底合成仅用于透明区域检查，保留原始PNG；图像显示圆角和上下间隙，不能证明动画全过程无黑边。白底检查图build68-expanded-on-white-inspection.png。

后续CUA收起操作明确返回Mac锁屏且无法自动解锁；该操作无有效验收结果，不计通过/故障。已请求用户手动解锁。未启动两小时观察，不将锁屏状态混入有效播放验收。图片含真实第三方专辑封面，保持本地QA，不放入公开README或推送。

证据：.build/qa/build68-install-receipt.json、build68-controls-*.json、build68-menu-exit-samples.json、build68-expanded-alpha-summary.json及上述图片；回滚receipt保留。当前68已安装，274自动测试和镜像检查是候选时完成；全屏修复尚未在68实测。Goal active，其他完整门禁仍开放。
