# build103 歌词层级与展开高度验收

## 变更

- 读取器在通过同一歌曲标题、完整艺人和歌词语料门禁后，发布当前段落以及相邻的下一段完整歌词。
- 紧凑态继续只显示当前原文，避免顶部 33pt 区域出现双行裁切。
- 展开态歌词卡片调整为 68pt，带歌词 body 调整为 236pt，容纳当前原文、译文和下一句。
- 下一段与当前段重复时不重复显示，未通过同一语料校验时不显示。

## 验证

- `swift test --quiet`：295 项通过。
- `Scripts/verify-qishui-control-safety.sh`：通过。
- `git diff --check`：通过。
- `/Applications/顶屿.app`：`0.1.3 (103)`，严格签名通过。
- 真实汽水音乐实机样本：`Beat Have My Back / Type Beats Trap`。
- 紧凑态真实画面：显示 `I'm so lonely`，单行无黑边、无底部裁切。
- 展开态真实画面：同时显示 `I'm so lonely`、`我好孤独`、`Envy you go crazy`，下一句完整可见，卡片底部无裁切。
- 真实调试读取：`Homesick (Prod. by Primary) / Benzamin` 发布当前原文、当前译文、下一段原文和下一段译文，且 MediaRemote 与汽水 AX 身份一致。

## 未宣称

- 本记录不宣称所有汽水曲目都有歌词；纯音乐或未暴露歌词的曲目仍按无歌词状态显示。
