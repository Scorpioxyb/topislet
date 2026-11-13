# build59 DMG 与长稳资源诊断

上一轮d5698ac已完成歌词源码、270项测试与Release应用候选；本轮继续阶段0，未安装或停止监测中的build56/37264。机器18:42:12Z再次锁屏，解锁请求已发，交互门禁仍未完成。用户后来禁止百度网盘验收，仍遵守该限制。

## Release链路修正及候选

build-release.sh原Finder AppleScript布局段改为直接写入自有挂载镜像的.DS_Store，不操作Finder或用户设置。新增create-dmg-layout.py及仅构建使用的固定版本ds_store1.3.3/mac_alias2.2.3，依赖在.build/dmg-tools虚拟环境安装；README和CI/Release workflow加入显式依赖准备。实际写入两图标(170,190)/(490,190)、660×400窗口、128图标、背景alias。写入后重读验证；挂载最终只读DMG独立检查图标位置、窗口参数、alias目标/.background/background.png及卷名。尚未Finder视觉验收，不把布局数据检查冒充视觉通过。

首次新版脚本实际构建通过，但hdiutil返回行格式与旧awk挂载解析不符，产生失败而非有效DMG；当时已挂载镜像经hdiutil info确认，卸载后整个失败工作目录移到Trash。脚本改为显式受控mountpoint，不解析显示输出。第二次完整脚本exit0，签名、40个代码/数据段、plist、架构、最低系统版本、镜像、checksum检查通过。独立verify-release-dmg.sh也exit0。package-app.sh同样改为SwiftPM --show-bin-path及签名后section比对，本轮未执行安装脚本以保留正在监测的App。

初始独立build59 App候选采用cdhash隐式designated requirement，而已安装56为identifier规则；这可能破坏升级后的现有AX授权匹配。开发候选的ad-hoc分支沿用package-app.sh已有的identifier designated requirement，Developer ID分支不更改。最终DMG的requirement与安装56逐字一致，不改TCC、不新增权限；实际授权连续性必须安装后验证。早期独立App候选仍保留，receipt明确其为较早stage，下一次安装应取最终DMG里的App。

最终DMG：.build/release-artifacts/build59/TopIslet-v0.1.3-arm64.dmg。
SHA256：7a3fcd7ba514efed874a4b8c2c8f4c5679c5ffd27722ed9e5f5ae18a65ac1b22。
版本0.1.3/build59，ad-hoc，未公证、未发布。receipt记录installed=false、finderVisualVerified=false、realMachineFinalCandidateVerified=false。

控制安全、脚本bash语法、布局Python语法、git diff检查通过。产品Swift源码本轮未更改，未重复全部270测试；完整Release脚本实际触发一次Release重新构建16.31秒，第二次增量0.18秒。

## 长稳门禁待终结，不能提前通过

同一22112句柄实际轮询仍live。18:50:42Z摘要863样本/4317.75秒，CPU平均0.0904%、P95约0.115%、内存结束口径RSS约-5.09%、footprint约+5.96%、最多1窗口，completed=false。曾有maximumSustainedChildGrowthSeconds=30.042秒；脚本只在终结时填violations，因此期间空数组不能算通过。

CSV中18:23:14–18:23:39的连续6行额外子进程PID每行不同（78881/78906/78919/78935/78948/78972）。5秒粗采样可能把周期性短查询连成“持续增长”；仅凭PID不同不能证明期间总数必然下降，因此不删原记录、不修改门禁来获得绿色结果。

补充只读90.052秒生命周期观察，目标37264基线子PID37266/37797，50ms计划间隔，1593实际样本，捕获28个额外PID，每个均在结尾消失，最长被采样连续增量0.0503秒。该新时段支持“当前额外子进程为短查询、非持久状态流”的判断，但不能倒推18:23历史间隙，不替代两小时门禁；没有记录每次实际采样间隙，50ms仅是计划间隔。产物.build/qa/build56-child-lifetimes.json。源码每2秒刷新通过单次perl get-client --no-artwork，有执行/终止界限；现存源码支持这一解释而非直接证明历史进程身份。

长稳包含锁屏、暂停、UI控制、源码构建，不能算持续音乐播放两小时。需同一句柄结束后审核原summary/CSV与环境记录；最终59仍需新的完整资源/持续播放验收。

## 待完成

解锁后继续实机三键、原生与伪全屏、Desktop2、逐帧黑边和全部命中区。监测结束后保留56回滚副本，从最终59 DMG安装并核验PID、签名/AX权限、三键与歌词卡片；后台新曲无法身份归属时歌词仍保守留空，不拉起汽水。关闭不重开600秒、异常恢复、生命周期、计时器/提醒恢复及最终版长稳仍未通过。Goal保持active。

## 可复用的子进程补充观察器

新增Scripts/observe-process-children.swift，显式输入目标PID/持续时间/采样间隔/输出文件，仅读取proc元数据；不输出参数或完整执行路径，只记录执行文件basename、PID、首末观察时间、命中次数、实际采样间隙、基线/末尾子PID。使用单调时钟；输出已存在、目标不存在、持续时间非法均在写入前拒绝。它是细采样旁证，不修改原monitor-long-run.swift或长稳门槛，不消除历史违规，亦不证明所有间隙内没有短进程或PID复用。

首次60.010秒/564样本，最大实际间隙0.111232秒，7个额外进程basename均为perl，每个只命中一次，末尾基线两PID37266/37797仍在。第一次版本CSV表头被首条记录覆盖；JSON有效，原CSV采用显式列名核对564行严格递增，保留原文件，不静默修写。修正FileHandle.seekToEnd后，独立15秒/142样本实测，正常表头、CSV/JSON数量、时间递增及最大间隙一致（0.110686秒）；对既有文件再次调用拒绝且JSON/CSV字节不变。非法nan时长及不存在PID均拒绝且未创建文件。原始产物分别.build/qa/build56-child-observation-2和-3的JSON/CSV，工具日志/tmp/topislet-build56-child-observation-2.log及-3.log。此为build56锁屏时段观察，不升级为build59通过。
