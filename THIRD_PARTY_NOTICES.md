# TopIslet Third-Party Notices

顶屿自身的源代码按 `GPL-3.0-only` 授权；以下组件保留各自许可证。

## MediaRemote Adapter

- Upstream project: [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)
- Upstream license: BSD 3-Clause License
- Bundled license text: `Vendor/MediaRemoteAdapter/LICENSE`
- Bundled framework metadata version: `0.1.0`
- Upstream release: `v0.7.6`
- Upstream commit: `3ac3d4bdf862c7b5399b4fba4df5689f5c38609a`
- Project patch: `Vendor/MediaRemoteAdapter/patches/topislet-client-targeting.patch`
- Rebuild script: `Scripts/rebuild-mediaremote-adapter.sh`

The application bundles `MediaRemoteAdapter.framework` and `mediaremote-adapter.pl`. The local adapter interface includes project-specific client-targeted commands used to read and control `com.soda.music` without following the system-wide current media focus.

The exact upstream commit, project patch, build command and byte-for-byte verification record are documented in `Docs/MEDIAREMOTE_ADAPTER_REPRODUCIBILITY.md`. The committed rebuild script reproduces the bundled universal framework with SHA-256 `3446ebb0889757c8d4cee0ac7a577bbbd530e3ba61225d30b47e3b85d31f95ab` on the recorded toolchain.

The BSD 3-Clause license requires its copyright notice, conditions and disclaimer to accompany source and binary redistributions. The release packaging script copies this notice into the App bundle.
