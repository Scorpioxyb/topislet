# MacBook 机型几何自适应验收

日期：2026-07-19

## 实现

- 顶屿运行时读取 `NSScreen.safeAreaInsets`、`auxiliaryTopLeftArea`、`auxiliaryTopRightArea`、屏幕 frame 与缩放比例。
- 带刘海屏使用两侧辅助区域之间的真实摄像头区域宽度、高度和中心，不再固定按屏幕中心定位。
- 无刘海外接屏使用 160pt 顶部居中胶囊；异常辅助区域不会被误判为物理刘海。
- 布局校准继续按显示器身份独立保存，系统屏幕参数变化后立即重新解析并定位。

## 本机结果

- 设备：MacBook Air 15 英寸，`Mac17,4`。
- 系统屏幕 frame：`1710 x 1107 pt`，缩放比例 `2.0`。
- 系统安全区顶部：`33 pt`。
- 摄像头区域：`x=763, y=1074, width=185, height=33 pt`。
- 摄像头区域中心：`x=855.5`；屏幕中心：`x=855`。顶屿现按前者定位，修复原有 `0.5 pt` 偏差。
- 默认 1pt 覆盖校准后，顶部胶囊高度为 `34 pt`。

## 自动化

- SwiftPM：`swift test`，141 项通过。
- Xcode 26.6：`xcodebuild -scheme MacBookIsland-Package -destination 'platform=macOS' test CODE_SIGNING_ALLOWED=NO`，141 项通过，`TEST SUCCEEDED`。
- 测试矩阵覆盖 MacBook Air 13/15、MacBook Pro 14/16、非零多屏坐标、无刘海外接屏和异常辅助区域。
- 首轮 GitHub CI 暴露网易云异步测试的固定 `250ms` 等待在 Runner 负载下不稳定；测试已改为最多 1.5 秒的有界条件等待，产品时序保持不变。

## 边界

- Xcode 不提供不同 MacBook 物理刘海模拟器；矩阵负责验证几何算法，最终像素贴合仍需对应真机截图验收。
- 本轮不维护机型型号到固定尺寸的映射；未来机型继续优先使用 macOS 实际返回的屏幕几何。
