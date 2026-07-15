# 2026-07-16 单窗口动画回归

## 自动验收

运行 `swift Scripts/verify-island-window-animation.swift`，结果：

- WindowServer 全程只有一个顶屿窗口。
- 紧凑态为 `377x34`，展开态为 `460x190`。
- 展开和收回期间水平中心与顶边误差不超过 `0.75pt`。
- 透明动画画布只在紧凑和展开目标尺寸间切换，没有第二层窗口插值。
- 鼠标进入后保持 12 秒，连续 3 次回归中窗口均持续为 `460x190`，没有瞬时展开后自行收回。
- 脚本结束后鼠标回到原位置。

## 视觉证据

本机保留以下不进入 Git 的验收产物：

- `.build/acceptance-artifacts/topislet-animation-final-20260716.mov`
- `.build/acceptance-artifacts/topislet-animation-final-frames/`
- `.build/acceptance-artifacts/topislet-expanded-hold-v4.png`

逐帧检查覆盖：

- 紧凑态保持屏幕中线。
- 展开外壳从顶部锚点连续形变，内容随后淡入。
- 稳定展开态显示封面、歌曲、歌手、进度、三枚控制和来源 Logo。
- 顶部 Header 与展开 Body 保持 8pt 间距。
- 收回前内容淡出，外壳回到原中心，没有向右偏移后再复位。

## 结论

结构、逐帧检查和产品负责人最终 MOV 人工视觉验收均通过，可以进入发布收尾阶段。
