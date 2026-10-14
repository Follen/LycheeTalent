# 开发与验证

生产文件在 `addon/`，包含主包和 13 个按需加载的职业数据包。Lua 5.1、Python 3（采集器使用标准库）、PowerShell 用于本地检查与打包。

```powershell
lua tests/run.lua
lua tests/talent_ex.lua
lua tests/ui_smoke.lua
lua tests/ui_smoke.lua list-scroll
lua tests/ui_smoke.lua reorder
lua tests/build_order.lua
lua tests/ui_smoke.lua same-build-refresh
lua tests/ui_smoke.lua pending-prompt
lua tests/single_config.lua
lua tests/starter_build.lua
lua tests/actionbar_profiles.lua
lua tests/actionbar_restore.lua
lua tests/actionbar_edgecases.lua
lua tests/actionbar_edgecases.lua override
lua tests/actionbar_edgecases.lua pickup-fallback
lua tests/actionbar_edgecases.lua random-mount
lua tests/macro_identity.lua
lua tests/unreadable_macros.lua
lua tests/actionbar_capture_events.lua
lua tests/actionbar_capture_events.lua deferred
lua tests/inactive_hero.lua
lua tests/native_open.lua
lua tests/reminders.lua
lua tests/catalog_business.lua
lua tests/motion.lua
Get-Content -Raw analyze/IconDataProvider.lua | lua tests/icons.lua
Get-Content -Raw analyze/IconDataProvider.lua | lua tests/icon_provider_lifecycle.lua
lua tests/data_memory.lua MAGE 500
python -m unittest discover -s tests -p 'test_*.py'
powershell -File tools/package.ps1
```

`test_data_publication.py` 的完整等价性比较需要本地采集数据库；没有数据库会明确 skip，其他纯逻辑测试无需凭据。离线替身测试不能证明原生 API、taint 或真实帧时间。

两个图标测试的标准输入需要完整的暴雪 `Interface/AddOns/Blizzard_FrameXMLBase/IconDataProvider.lua`。本次固定源码为 `Gethe/wow-ui-source` 提交 `09b9db7948abc9b9648dedaab51eb0cf3ee67b31`；通过 LycheeDev `source inspect` 提取 `result.text` 到忽略目录 `analyze/IconDataProvider.lua`。不要把原始源码、实机记录或角色数据提交到仓库。

“我的方案”支持拖动行排序，红线表示落点，靠近列表边缘会自动滚动。松手保存当前专精的顺序，拖到列表外或按 Escape 取消；编辑不改变顺序，新增方案排在已排序方案后。排序不应用天赋。图标选择默认进入“常用”，完整法术、物品目录分别在首次切到对应分类时加载。

## 更新推荐

凭据保存在项目外，支持 `WCL_CLIENT_ID` / `WCL_CLIENT_SECRET` 环境变量，也可向 `tools/wcl/collect.py --credentials` 传入本地文件路径。不要把凭据提交到仓库。原始 SQLite 数据库位于忽略的 `data/private/`。

采集前检查游戏补丁、赛季、场景与观察窗口。不能只改版本标签冒充新数据。`data/publication.json` 记录采集时间及数量；生成的职业分片随源码提交。

奶骑大秘境固定使用快乐阳阳（国服霜之哀伤，WCL 角色 ID `112885599`）的方案：在观察窗口内，选择有公开日志的最高限时层数，同层取用时最短的一场，并从该场奶骑的原始天赋树读取完整加点。超时、无日志记录不参与，不生成其他玩家的热门方案。团本及其他专精保持原采集规则。局部刷新时，`class_collected` 记录受影响职业分片的时间，`collected` 保留上一轮全量采集时间。

## 模块

| 模块 | 职责 |
| --- | --- |
| Core / Dock | 命令、原生窗口联动、按需初始化 |
| Storage | 个人方案与存储 |
| Catalog / Scenarios | 职业目录与场景 |
| Talents / Apply | 格式校验、天赋转换、单原生方案与事务确认 |
| ActionBars / Reminders | 动作条布局、到场提醒 |
| UI / Icons / Motion / Locales | 界面、图标目录、动画、中英文 |

安装脚本 `tools/install.ps1 -AddOnsPath <目标AddOns目录>` 复制并核对文件哈希，不发送游戏输入。打包脚本逐文件校验 ZIP；发布物只包含插件文件及协议、第三方声明。截图、原始诊断、角色资料和采集数据库不进安装包。

单角色已验证原生方案复用及 180 槽动作条往返。跨副本、首领区域触发、跨职业、重新登录、taint 和完整帧时间仍有覆盖边界。性能见 [PERFORMANCE.md](../PERFORMANCE.md)。

完整动作条读取、切换前保存、恢复、校验与最终保存由 `Apply.op` 管理，首次默认布局也在第一次应用时捕获。点击后先显示“应用中”，下一帧开始读取；关闭面板不取消事务，完成全部操作和保存后才结束。后续图标通知不再启动主动读取。首次捕获失败保留已有恢复备份。

动作条布局只在切换前读取并保存当前方案，恢复后核对并保存目标方案；不注册动作条刷新、鼠标变化、宏编辑或退出事件，也不挂接拾取、放置、宏删除函数。日常拖动由原生动作条保存，下次切换读取当时的实际布局；重载后仍通过原生方案和天赋匹配确认当前布局归属。共用布局和独立布局分别保存，互不覆盖。

宏仍按绝对编号区分。`GetActionInfo` 没有子类型时直接读取宏编号；有技能／物品子类型时才在切换期间复制到光标读取。恢复时使用准确编号调用 `PickupMacro`，不按名称或正文匹配，不创建或编辑宏。差异恢复和已有技能查找使用本次快照，写入结束统一核对，不在查找过程中反复读取宏。旧快照中的不可读占位符在当前槽位可读时更新为实际动作。

`actionbar_capture_events.lua` 覆盖 500 次独立刷新、同步／延迟通知、同名宏交换和删除后在切换时保存、重载及退出时保留用户光标。`macro_identity.lua` 覆盖普通宏直接读取、带子类型宏的准确编号读取、61 槽旧占位符恢复及缺失宏报错。`single_config.lua` 覆盖单配置复用、共用／独立布局往返、重载后保存、读取前显示进度和首次读取失败。以上均为离线 API 替身；本次按用户要求不做实机验证，第 61 槽的实际返回值尚未取得。
