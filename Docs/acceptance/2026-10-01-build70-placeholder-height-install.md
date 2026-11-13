# build70 占位歌词高度修正与安装

- 提交基础：`35fea54` 歌词独立栏；本次改动将音乐面板高度判断改为使用清洗后的歌词行，避免 `纯音乐，请欣赏` 等占位文本撑高空白面板。
- 版本：`0.1.3 (70)`。
- DMG：`.build/release-artifacts/build70/TopIslet-v0.1.3-arm64.dmg`。
- DMG SHA256：`ee71427606892d0f8e18069fedb5261474f7c26481ad3e68d94e359c3deee4bb`。
- 安装二进制 SHA256：`a219846382c966cea350e8ce8e5658249c9710acc10190ee709c29316833ea3e`。
- 274 项 Swift 测试通过；Release、签名、DMG 校验和40段二进制一致性通过。
- build69 已按回收站策略移走，build70 安装并启动，主 PID `26350`；当前只有一个主进程和两个状态流子进程。
- 当前汽水 AX 只返回占位歌词且 MediaRemote 未形成可信来源，因此没有伪造展开歌词截图；紧凑态窗口仍为 `377x35+666+-1`。
- 安装后回归：`bash Scripts/verify-qishui-control-safety.sh` 通过，`swift test` 全部274项通过，`git diff --check` 通过。

状态：build70 是当前候选，不是阶段0封版。待可信播放和真实歌词出现后，需要再做一次展开歌词栏、按钮命中、黑边和收起恢复验收。
