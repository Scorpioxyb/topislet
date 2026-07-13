# 汽水专属流并存回归

日期：2026-07-13

## 环境

- 汽水音乐、抖音、QuickTime Player、Chrome 和 Safari 同时运行。
- 顶屿使用 `stream-client com.soda.music` / `get-client com.soda.music` 读取汽水状态。
- 系统当前媒体诊断结果为 `verifiedQishuiSource=false`、`currentTrack=nil`、来源 `unknown`。

## 结果

连续 5 次汽水专属读取均返回：

- `verifiedQishuiSource=true`
- `source=MediaRemote Adapter Stream`
- `duration=177.435941`
- 封面数据 `12967 bytes`

播放进度依次为：

```text
0.6400662582
0.6517077227
0.6635131200
0.6752524897
0.6869738016
```

## 结论

- 系统当前媒体来源不能确认时，汽水专属流仍持续输出同一首歌曲的可信递增进度。
- 抖音、QuickTime 和浏览器进程存在，没有把顶屿的数据源替换成系统当前媒体。
- 本轮没有检测到抖音可读取的 MediaRemote client，因此只确认数据隔离；播放控制不误控视频仍由汽水 PID 内唯一语义 AX 控件门禁和后续实机播放回归共同验收。
