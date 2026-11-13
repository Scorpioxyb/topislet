# 联合观察工具准备，未开始新的两小时验收

当前安装68，主28073、状态流28074/28075、汽水37785。只读会话检查确认locked=true、frontIsLoginWindow=true，进程仍运行。本轮不进行CUA或启动正式观察，未重启/替换/故障注入，锁屏阻碍仍待用户手动解锁。

## 改善观察方法

新增Scripts/run-playback-observation.py及playback-observation-session.swift。准备步骤先编译资源、细子进程及会话只读探针；正式启动不再等待Swift解释编译。启动前检查唯一目标PID/启动时间、已知未锁定会话及安装build，拒绝已有观察prefix，避免误覆盖或重复启动。默认各观察7215秒，近同时启动；15秒启动余量不是通过条件，终局仍按原共同7200秒审核。

四项保持原资源/子进程脚本门槛，新增播放与事件观察保留同PID及真实接收时间；播放采样同时记录会话与启动时间匹配。只允许布尔/有限非负数字/PID值白名单，不落盘歌名、封面、歌词、账户、诊断或配置。事件时间验证ISO格式，完整EVENT边界/末尾记录落盘；observer有截止及输出上限，只有自行创建的独立观察进程组可被超时终止，不控制产品或汽水。

主包装器等待四项终局并记录结果，随后运行联合audit；原始resource violations、15%内存门槛、CPU/线程/子进程时间门槛及单窗口要求不变。新增锁屏/未知会话/进程身份变化样本使采样门禁失败。即便全部采样门禁干净，continuousPlaybackAcceptanceProven仍false：采样间隔的状态和实际交互仍需另外核实，不把准备完成或空违规列表当封版。

## 已执行

`python3 Scripts/run-playback-observation.py --prepare-only`完成，明确observersStarted=false。三个观察工具已编译至.build/qa/observer-tools/34776c343dd351db/。

实际锁屏启动检查返回exit2及“session locked/unknown or target identity unavailable; observers not started”，未产生build68-locked-start-probe观察文件。证据.build/qa/build68-preflight-locked.txt。此前一次日志输出与prefix同名，先触发已有prefix拒绝，保留build68-lock-refusal-result.txt，不把那次当锁屏检查。

`python3 -W error::ResourceWarning -m unittest discover -s Scripts/tests -p test_playback_observation.py`8测试通过：内容过滤、异常值、来源缺失/不匹配、锁屏/未知会话、重复身份、旧文件不可覆盖、两个事件含末尾保存及共同两小时合成数据中锁屏/原45%内存失败保留。合成测试只验证审计工具，不是产品性能证据。小型临时fixture保留，普通清理须使用Trash。

原61终局回归共同7073.689878秒、footprint45.0428255%、sampledEvidenceGatesSatisfied=false、continuousPlaybackAcceptanceProven=false仍保留。证据.build/qa/build61-joint-audit-observer-tool-regression.json。

## 后续正式运行

必须先解锁并完成当前版本需要故障注入/退出的实机矩阵，再核实实时PID与安装build，以新prefix启动；运行中不重启、安装替换或注入故障。当前PID仅记录本轮状态，不直接作为未来可用保证。

```sh
python3 Scripts/run-playback-observation.py --prefix .build/qa/build68-joint-run1 --parent-pid 28073 --source-pid 37785 --expected-build 68
```

本轮没有执行该正式命令。未来应以返回的工具session/进程句柄确认存活和终局；receipt不代替活进程检查。不因超时快照或旧文件重新启动观察。Goal仍active，68全屏、Desktop2、关闭/恢复、动态黑边、当前候选性能及后台任意新歌歌词仍开放。
