# TopIslet Third-Party Notices

顶屿自身的源代码按 `GPL-3.0-only` 授权；以下组件保留各自许可证。

## MediaRemote Adapter

- Upstream project: [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
- Upstream license: BSD 3-Clause License
- Bundled license text: `Vendor/MediaRemoteAdapter/LICENSE`
- Bundled framework metadata version: `0.1.0`
- Upstream release reviewed during release preparation: `v0.7.6`

The application bundles `MediaRemoteAdapter.framework` and `mediaremote-adapter.pl`. The local adapter interface includes project-specific client-targeted commands used to read and control `com.soda.music` without following the system-wide current media focus.

Before publishing a binary Release, the project must record the exact source repository, commit, local patch set and reproducible build command for the bundled framework. The current repository contains the binary and BSD license, but not the complete corresponding modified framework source. This remains a release blocker for a fully reproducible public binary.

The BSD 3-Clause license requires its copyright notice, conditions and disclaimer to accompany source and binary redistributions. The release packaging script copies this notice into the App bundle.
