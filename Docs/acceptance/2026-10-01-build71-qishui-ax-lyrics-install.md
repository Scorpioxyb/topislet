# build71 汽水 AX 歌词路径候选安装

- 改动：当 MediaRemote 不可用但汽水 AX 已取得同 PID、同歌名、同歌手且未过期的歌词快照时，`QishuiDirectTrack` 不再丢弃歌词；桌面歌词快照标记同步保留。
- 提交基础：`19f42ba` 及本次 AX 路径修正。
- 版本：`0.1.3 (71)`。
- DMG SHA256：`f72b453c437a753064c9919e0265bc2e8f400f7015af4b373753b571ae6fcde2`。
- 安装二进制 SHA256：`bc9772180d80f20b5dc44d01937b32a750e2a409181ad6ab1a64e3f676701d6d`。
- 274 项测试通过；控制安全、Release、签名、DMG 和40段二进制校验通过。
- build71 已安装并启动，主 PID `29852`；旧 build70 已移入废纸篓。
- 当前汽水仍只返回占位歌词“纯音乐，请欣赏”，因此真实歌词栏截图和实机命中测试仍待可信歌词出现后完成。
- 后续只读复核仍显示 `controlAvailability=available / allowsControl=true`，但 `adapter-status` 为 `verifiedQishuiSource=false / currentTrack=nil`；这证明当前阻碍是没有可信播放数据，不是控件权限或唯一性失败。

状态：build71 是当前歌词候选，不是阶段0封版。歌词来源门禁没有放宽到无身份或过期快照。
