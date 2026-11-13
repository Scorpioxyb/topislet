# build60 几何观察与build61时长修正

起始解锁，安装60/主32173，汽水37785隐藏且最小化、暂停。运行verify-island-window-animation.swift --observe-only，不运行默认合成输入模式。实际CUA紧凑标题点击展开，再按即时收起按钮回紧凑。观察session10425正常exit0：20.0031秒/7798样本、平均389.84Hz、maxGap18.319ms、中心误差0.500pt/顶边漂移0，窗口始终1；紧凑377×35、展开460×191。数据见/tmp/topislet-build60-passive-animation.log；该脚本没有保存逐样本原始CSV，结论限定为此次观察汇总，不当成完整逐帧渲染证据。

第二次展开请求后collapse missing，未执行收起，不计成功。重新读取为紧凑；实际再展开，截图标题/歌手/进度/封面/三键无明显裁切。实际最小化按钮进入折叠，截图245pt宽胶囊；折叠图像点击返回紧凑，与CollapsedIslandTapPolicy一致。静态截图不能证明逐帧黑边、透明区全部命中或80ms反向序列。

审查发现IslandMotion.duration与测试仍为展开280ms/收回200ms，与QA_CHECKLIST明确240±16.7ms/180±16.7ms不符。build61源码改为240ms/180ms，geometryAnimation与AppKit frame共用该值；reduceMotion仍0。相应回归测试更正为验收要求，完整270项通过，控制安全及diff检查通过。已安装仍60；build61需要构建/镜像安装及实际时长/反向验证，不能用源码值宣布渲染时长通过。

CUA kernel reset并精确TERM服务35450，复查两种helper无残留。最终安装60保持单窗口紧凑、汽水隐藏/最小化/暂停。Goal active，未发布。

61 ARM64 Release17.04秒完成；完整DMG脚本及独立镜像签名/40代码数据段比对通过。候选.build/release-artifacts/build61/TopIslet-v0.1.3-arm64.dmg，SHA256 6e4bc70cd19cd3a7d07087d2a3a97f1db3723a16dc37a76789b9fb333fd9fe82。未安装61，未以候选替代当前60实机门禁。
