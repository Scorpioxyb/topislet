# MediaRemote Adapter 供应链与可复现构建

## 上游基线

- 项目：`ungive/mediaremote-adapter`
- 地址：<https://github.com/ungive/mediaremote-adapter>
- 标签：`v0.7.6`
- commit：`3ac3d4bdf862c7b5399b4fba4df5689f5c38609a`
- 上游及本地许可证：BSD 3-Clause

仓库内的 `topislet-client-targeting.patch` 在该 commit 上增加按 Bundle ID 读取指定 MediaRemote client 的 `get-client`、`stream-client`，以及只允许播放/暂停、上一首、下一首的 `send-client` 能力。补丁不修改汽水音乐 App，也不包含汽水音乐的解包源码或账号数据。

顶屿运行时通过系统 `/usr/bin/perl` 加载随 App 分发的 Adapter，用于汽水专属状态流与诊断；Adapter 脚本中的 `send-client com.soda.music COMMAND` 只保留给源码级研究，不再由顶屿二进制暴露或调用。产品控制使用汽水唯一语义 AX 控件，不再运行或分发 `/usr/bin/python3` 控制脚本。

## 当前发布二进制

| 文件 | SHA-256 |
| --- | --- |
| `MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter` | `6de4ad829488b12e2b969ddf17e2459f855781b2130f8fb554a40958fe224374` |
| `mediaremote-adapter.pl` | `16d37cfdc7886f1f8908a356c0199eb1f0f31a365d3aa705dad73a586cf5392d` |

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
