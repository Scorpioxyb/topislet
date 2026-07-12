# MediaRemote Adapter 供应链与可复现构建

## 上游基线

- 项目：`ungive/mediaremote-adapter`
- 地址：<https://github.com/ungive/mediaremote-adapter>
- 标签：`v0.7.6`
- commit：`3ac3d4bdf862c7b5399b4fba4df5689f5c38609a`
- 上游及本地许可证：BSD 3-Clause

仓库内的 `topislet-client-targeting.patch` 在该 commit 上增加按 Bundle ID 读取指定 MediaRemote client 的 `get-client` 和 `stream-client` 能力。补丁不修改汽水音乐 App，也不包含汽水音乐的解包源码或账号数据。

项目另有 `qishui-targeted-control.py`，用于把播放、暂停、上一首和下一首命令限制到 `com.soda.music`。它是顶屿项目源码，不是上游文件或第三方二进制。

## 当前发布二进制

| 文件 | SHA-256 |
| --- | --- |
| `MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter` | `3446ebb0889757c8d4cee0ac7a577bbbd530e3ba61225d30b47e3b85d31f95ab` |
| `mediaremote-adapter.pl` | `70c56f2263ff1476629e00d30ca2718497b7fc9ebe6e9125849a1c4bb7bcd7c5` |
| `qishui-targeted-control.py` | `16ad6bc1f0c5a6c4da8f0650c1e31c0c01acc8d16d9cca63abaa96eb18dcb8ce` |

已确认当前 Framework 同时包含 `arm64` 和 `x86_64`，并可使用下述脚本从固定上游 commit 和仓库补丁逐字节重建。

## 重建

要求：macOS 26.5 SDK、Apple clang 21.0.0、Git 以及网络访问。当前已验证环境为 macOS 26.5.2、SDK 26.5（build `25F70`）、Apple clang `21.0.0 (clang-2100.1.1.101)`。

```bash
bash Scripts/rebuild-mediaremote-adapter.sh
```

脚本会：

1. 克隆并检出固定 commit。
2. 应用仓库内的 client-targeting 补丁。
3. 分别编译 arm64 与 x86_64。
4. 合并并 ad-hoc 签名 Framework。
5. 对二进制、Perl 入口和 BSD 许可证执行逐字节比较。

成功出口必须显示：

```text
Reproducible byte-for-byte match: true
```

如果 Apple clang 或 SDK 变化导致二进制哈希改变，应先完成源码审计和功能回归，再有意识地更新 Vendor 二进制及本文哈希，不能跳过比较门禁。
