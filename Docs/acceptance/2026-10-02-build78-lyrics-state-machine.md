# build78 歌词呈现状态机收敛

状态：本地 Release 候选，Goal 仍进行中；未封版、未发布。

## 改动

- 新增 `MusicLyricPresentationState`：`unavailable` 或 `current(primary, translation)`。
- 收起态、紧凑态以及紧凑宽度判定统一调用 `MusicLyricPresentation.state`，不再分别清洗和配对歌词。
- 状态机继续保留 build77 的换行拆分、占位行过滤和中英配对规则。
- 新增测试确认从译文索引进入时仍返回同一主句/译文，并确认占位歌词返回 `unavailable`。

## 验证

- `swift test --quiet`：286 项通过。
- `Scripts/verify-qishui-control-safety.sh`：通过。
- 本记录创建后需以 build78 Release 安装结果作为最终安装证据。

## 尚未关闭门禁

- build78 安装后的自然汽水歌词截图和长句完整滚动周期。
- AX 唯一活动行归属、切句延迟、资源占用、多屏、全屏、黑边和 Reduce Motion。

结论：状态计算已收敛并通过单元测试，Goal 仍需 build78 实机回归。
