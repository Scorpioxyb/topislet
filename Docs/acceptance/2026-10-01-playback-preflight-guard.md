# 两小时观察启动前播放检查

当前安装68、主28073、源37785启动时间保持，sessionKnown=true/locked=false/frontIsLoginWindow=false。ps未发现联合/资源/细子进程观察进程；没有正在运行的两小时验收需等待。

独立只读adapter预检确认verifiedQishuiSource=true、sourceProcessIdentifier=37785，但isPlaying=false；源hidden=true/mainMinimized=true。没有替用户恢复播放。证据.build/qa/build68-joint-preflight-source.json仅白名单与歌曲指纹，不存正文。

发现联合启动器原只检查会话/进程/build，允许暂停状态启动正式观察。新增source_preflight：adapter读取8秒超时，要求exit0、可信同PID且playing=true；失败在写launch receipt或启动任何观察器前退出。读取状态后再次核对解锁会话及两个进程的启动身份，避免沿用读取前状态。receipt只保存格式验证白名单。该改动属于验收工具，未修改已安装产品。

10项工具测试通过，新增暂停/exit非零拒绝与可信播放内容过滤。实际启动命令返回exit2“trusted target source is not playing or probe failed; observers not started”；build68-joint-run1-*文件为空，ps仍无观察进程。证据.build/qa/build68-playing-preflight-check.txt。不把拒绝启动当两小时验收通过或产品故障。

已请求用户方便时恢复播放；未修改当前暂停状态或系统设置。后续须重新检查实时会话/PID/build再开始观察，不能把此处暂停状态泛化为未来状态。Goal保持active，剩余实机与性能门禁未缩减。
