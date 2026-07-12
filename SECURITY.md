# Security Policy

## Supported versions

当前只维护最新的 `v0.1.x-alpha` 开发分支。正式版本发布后，本表会按实际支持范围更新。

## Reporting a vulnerability

请不要在公开 Issue 中披露可直接利用的漏洞、隐私数据、权限绕过方法或用户凭据。

请使用仓库的 GitHub Private Vulnerability Reporting 私密提交安全问题；不要把漏洞细节发布到公开 Issue。

报告建议包含：

- 受影响版本或 commit
- macOS 和设备信息
- 影响范围
- 最小复现步骤
- 建议缓解措施

## Security boundaries

- 项目不应抓取账号 token、执行 MITM、修改汽水 App 或发送全局媒体键。
- 辅助功能产品控制必须只绑定汽水 PID，并且只在语义目标唯一时执行。
- MediaRemote client 命令不得用于产品控制；辅助功能未授权或语义目标无法唯一证明时应安全失败，不应把控制命令转发给系统当前媒体源。
