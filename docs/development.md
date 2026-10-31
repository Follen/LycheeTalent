# 开发与验证

生产文件在 `addon/`，包含主包和 13 个按需加载的职业数据包。Lua 5.1、Python 3（采集器使用标准库）、PowerShell 用于本地检查与打包。

产品范围与业务规则见 [product.md](../product.md)，界面与交互见 [Design.md](../Design.md)，模块、数据和应用流程见 [architecture.md](../architecture.md)。本文负责开发操作、检查入口与验证边界。

```powershell
lua tests/run.lua
lua tests/storage_reset.lua
lua tests/talent_ex.lua
lua tests/ui_smoke.lua
lua tests/ui_smoke.lua list-scroll
lua tests/ui_smoke.lua reorder
lua tests/build_order.lua
lua tests/ui_smoke.lua same-build-refresh
lua tests/ui_smoke.lua pending-prompt
lua tests/ui_smoke.lua hero-controls
lua tests/hero_selection.lua
lua tests/catalog_loading.lua
lua tests/ui_smoke.lua data-errors
lua tests/current_build_cache.lua
lua tests/talent_read_entries.lua
lua tests/talent_stage_order.lua
lua tests/apply_event_burst.lua
lua tests/core_spec.lua
lua tests/actionbar_spec_ready.lua
lua tests/persisted_macro_readiness.lua
lua tests/actionbar_cursor_events.lua
lua tests/actionbar_config_events.lua
lua tests/actionbar_observation_routes.lua
lua tests/actionbar_snapshot_reads.lua
lua tests/macro_observation_changes.lua
lua tests/ui_smoke.lua event-filter
lua tests/single_config.lua
lua tests/native_partial_load.lua
lua tests/starter_build.lua
lua tests/actionbar_profiles.lua
lua tests/actionbar_restore.lua
lua tests/inactive_actionbar_spells.lua
lua tests/inactive_actionbar_spells.lua deferred
lua tests/actionbar_edgecases.lua
lua tests/actionbar_edgecases.lua override
lua tests/actionbar_edgecases.lua pickup-fallback
lua tests/actionbar_edgecases.lua random-mount
lua tests/macro_identity.lua
lua tests/macro_reference_failures.lua
lua tests/unreadable_macros.lua
lua tests/actionbar_capture_events.lua
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

`test_repository.py` 检查 TOC 加载路径与 Lua 覆盖、随包协议一致性、文档本地链接，以及中英文平台 Markdown／HTML 文本一致性。

`test_data_publication.py` 的完整等价性比较需要本地采集数据库；没有数据库会明确 skip，其他纯逻辑测试无需凭据。离线替身测试不能证明原生 API、taint 或真实帧时间。

`tests/run.lua` 和 `tests/inactive_hero.lua` 还依赖 Lua BitOp（`require("bit")`；LuaJIT 也提供此模块）。它们读取以下固定暴雪源码，`tests/native_open.lua` 读取原生天赋框体源码：

| 忽略目录中的目标 | 固定提交内的源文件 |
| --- | --- |
| `analyze/Blizzard/ExportUtil.lua` | `Interface/AddOns/Blizzard_SharedXMLBase/ExportUtil.lua` |
| `analyze/Blizzard/Import.lua` | `Interface/AddOns/Blizzard_PlayerSpells/ClassTalents/Blizzard_ClassTalentImportExport.lua` |
| `analyze/Blizzard/Frame.lua` | `Interface/AddOns/Blizzard_PlayerSpells/ClassTalents/Blizzard_ClassTalentsFrame.lua` |

两个图标测试的标准输入需要完整的暴雪 `Interface/AddOns/Blizzard_FrameXMLBase/IconDataProvider.lua`。本次固定源码为 `Gethe/wow-ui-source` 提交 `09b9db7948abc9b9648dedaab51eb0cf3ee67b31`；通过 LycheeDev `source inspect` 提取 `result.text` 到忽略目录 `analyze/IconDataProvider.lua`。不要把原始源码、实机记录或角色数据提交到仓库。

拖动排序与图标选择器的交互见 [UI/UX 设计](../Design.md)。相关检查入口为 `tests/build_order.lua`、`tests/ui_smoke.lua reorder` 及两个图标测试。

## 更新推荐

凭据保存在项目外，支持 `WCL_CLIENT_ID` / `WCL_CLIENT_SECRET` 环境变量，也可向 `tools/wcl/collect.py --credentials` 传入本地文件路径。不要把凭据提交到仓库。原始 SQLite 数据库位于忽略的 `data/private/`。

`tools/wcl/client.py --query-file <文件> --output <忽略目录中的结果文件>` 是手动查询入口；`inspect.graphql` 用于核对 schema，`sample.graphql` 是固定场景的示例，两者不是自动采集任务。`collect.py` 读取同目录的场景本地化、首领排序和地图 JSON；生成职业包 TOC 时继承主包的版本与 Interface，避免刷新数据后降回旧版本。

采集前检查游戏补丁、赛季、场景与观察窗口。不能只改版本标签冒充新数据。`data/publication.json` 记录采集时间及数量；生成的职业分片随源码提交。

`--class-name` / `--limit` 使用与现有发布一致的完整本地数据库，只更新实际新采或恢复发布的职业。局部采集保留全量 `collected`，记录受影响的 `class_collected` 和 `partialCollection.jobs`；全部命中缓存且没有待恢复结果时，不重写公开文件。失败 job 回滚自身事务，其他成功结果留在数据库供下次恢复，失败批次不发布。

`fill_missing.py` 续查本批缺口并保存原始响应和队列；原发布 ID 固定保留，本轮新增 ID 只接受更高限时层数、同层更快或更高对应团本指标。局部树先按唯一演员补取 CombatantInfo/Summary，再核对固定构建的完整参考预算、entry/rank 和英雄选择；明确拒绝读取的来源记录原因后跳过。`--max-page` 保留下一页状态，`--improve-only` 复核本轮已补记录。当前覆盖与已查页数见 [覆盖快照](recommendation-coverage-20261031.md)。

采集选择规则（包括各英雄系与毒牙祭坛奶骑的要求）见 [产品定义](../product.md#推荐数据)。局部刷新与全量采集的时间字段见 [架构说明](../architecture.md#数据采集与发布)。

## 安装与打包

安装脚本 `tools/install.ps1 -AddOnsPath <目标AddOns目录>` 复制并核对文件哈希，不发送游戏输入。写入前完成全部包的版本、源文件、TOC/XML 加载闭包和旧安装回执核对；目标存在外部修改或不同内容的未登记同名文件时停止，不覆盖。保留无关额外文件，已登记但不再发布的文件仅在旧哈希相符时删除。`test_install.py` 在临时 AddOns 目录检查这些行为，不使用正式服目录。

打包脚本逐文件校验 ZIP，只包含插件文件及协议、第三方声明；Lua/XML 必须在加载闭包内，源目录不接受重解析点，XML 禁止 DTD。`test_package.py` 分别运行 Windows PowerShell 5 和 PowerShell 7，检查未加载文件拒绝、加载引用与输出路径。截图、原始诊断、角色资料和采集数据库不进安装包。

单角色已验证原生方案复用及 180 槽动作条往返。跨副本、首领区域触发、跨职业、重新登录、taint 和完整帧时间仍有覆盖边界。性能见 [PERFORMANCE.md](../PERFORMANCE.md)。

## 动作条检查覆盖

动作条的读取时机、保存归属与宏身份处理见 [架构说明](../architecture.md#应用事务与动作条) 和 [天赋应用与动作条](talent-application.md)。

`macro_identity.lua` 覆盖原生宏满位复用、共享最新正文、删除与重编号、同名歧义、替代编号拒绝、原生 LF 表示差异。`actionbar_capture_events.lua` 同时运行同步与延迟通知，确认编辑观察不碰光标、删除保留待恢复原文、手动替换取消对应待恢复记录。两者使用 `macro_runtime.lua` 的原生 API 替身，插件宏写入次数必须为零（替身模拟的玩家编辑单独计数）。`macro_reference_failures.lua` 注入写槽失败、放置期间目标宏消失与槽位回滚失败，检查真实错误、目标备份和暂停保存。旧正文创建／编辑／删除事务检查已移除，因为这些行为不再属于插件。

`actionbar_profiles.lua` 验证默认共用、显式独立和专精隔离；`single_config.lua` 验证单配置复用、共用／独立往返、重载后保存、读取前显示进度、首次读取失败、目标布局无效时不提交天赋，失效原生宏不阻止提交并保留局部待恢复记录，以及回滚未完成后再次应用时保留原目标布局。`unreadable_macros.lua` 保留不可读宏槽位的回归检查。`single_config.lua` 还使用生产 Restore 实际制造已提交天赋后的写槽失败，覆盖回滚完成／未完成、混合结果、持久目标、登录及事件不能覆盖目标、显式动作条重试不再提交天赋。UI 替身检查默认未勾选和控件状态。

`native_partial_load.lua` 用噬灭“虚空净化”（节点 110174、入口 136699）模拟原生导入后已保存配置和 Ready 草稿同时遗漏一项请求等级，覆盖提交前补齐、目标已完整、节点不可购买、提交被拒绝、Starter 交接，以及首次新建／已有工作配置的完整应用路径。它使用生产准备与事务代码，原生返回值由替身提供，不是该角色的实机复现。

`storage_reset.lua` 核对生产 Store 的 V2 初始化矩阵、两个根独立重建、V2 数据幂等保留、旧个人方案／偏好／布局／宏登记丢弃，以及后续旧角色不能清空 V2 账号中新建方案。旧迁移模块和测试已移除；实际重建发生于客户端加载插件，不删除游戏保存文件或原生对象。

`inactive_actionbar_spells.lua` 复现旧布局中未学会技能导致的 `BARS_UNAVAILABLE`，覆盖其余动作恢复、待恢复位置保留、同步／延迟事件、独立布局、手动改槽、重载、重新学会后的恢复，以及已学会技能和物品的真实失败。正式服 12.1.5.70391 敏锐贼实机确认四个旧技能槽位无法拾取；隔离加载修复模块后，针对这些槽位的恢复与 180 槽核对通过，动作条和宏写入均为零。此检查没有替玩家应用天赋，也不代表完整更新后所有交互已验证。

## LycheeUI 内嵌检查

`addon/LycheeTalent/Libs/LycheeUI/.lock` 固定相邻源库 1.0.1 开发候选；内嵌前已核对清单完整性和全部 31 个 SHA-256。更新需整体同步已冻结源码与 Media，不在内嵌副本直接修补。主包 TOC 的 XML 入口加载完整十个模块，打包与安装必须递归包含 Libs。

`ui_smoke.lua` 加载真实内嵌库，并使用 Frame 替身验证 Context 生命周期、按钮及文字／面板接入、100 次窗口／对话框开关和固定行池。这个检查不渲染像素，不替代实际客户端的正常、悬停、按下、禁用和缩放验收。

`hero_selection.lua` 覆盖合法英雄组合、首次实际英雄优先、每专精记忆、M+／团本共用筛选、个人方案隔离和缺数据／未知值空态。`ui_smoke.lua hero-controls` 使用小型推荐 fixture 与真实 LycheeUI 分段控件，检查中文 API 双参数、只换列表不自动应用、专精重绑／旧双击失效、空态、100 次复用及待处理反馈清除；其余 UI 入口加载真实职业数据包。

`current_build_cache.lua` 使用生产 Apply／ActionBars、Talents 和固定原生序列化代码，检查反复读取当前方案只进行一次全树导出；相关事件先重新读取内容标记，变化、草稿、身份、专精、世界和打开 UI 时完整确认，目标条目原地变更也会失效。应用事务的成功核对不使用展示缓存。`ui_smoke.lua hero-controls` 同时核对原生英雄图集、元信息复用和悬停不创建提示框。实机前后测量见 [性能记录](../PERFORMANCE.md)。

`actionbar_spec_ready.lua` 与 `persisted_macro_readiness.lua` 通过生产事件入口复现登录早期专精 0／nil、原生宏尚不可读的状态，核对原有 V2 宏引用保留、就绪后恢复以及真实删除不误领替代宏。`actionbar_cursor_events.lua` 检查普通指针变化不再捕获／保存布局，待恢复专精仍等待光标清空，真实槽变和宏编辑继续保存。`single_config.lua` 保留失败恢复信息并核对成功重试不会删除最近失败摘要；UI 回归检查天赋确认后的部分恢复统一显示“已应用”。

`talent_read_entries.lua` 将直接节点读取结果与固定原生导出／解析结果逐字段比较，覆盖 Tiered 等级分摊、赠送节点、非活动英雄系、已保存配置、草稿、异常选择和缺少 helper／格式版本变化的回退。`ui_smoke.lua` 同时检查提醒的拖动、位置保存、隐藏时停止移动，以及主按钮正常、悬停、按下、禁用状态；实际鼠标命中仍需客户端验证。

`talent_stage_order.lua` 约束节点排序的原生元数据读取次数，并核对位置、ID 同位顺序与实际购买结果。`apply_event_burst.lua` 使用生产 Apply 状态机回放活动树先于保存配置更新的连续通知：每帧只核对一次，不提前成功，不轮询，同时覆盖原生加载、即时失败、战斗／专精中断、超时与所有事务计时器释放。该离线时序用例证明重复通知的开销边界，不表示真实客户端每次提交都会产生相同数量的通知。

`actionbar_config_events.lua`、`actionbar_observation_routes.lua` 和 `ui_smoke.lua event-filter` 检查配置 ID 过滤、元信息通知不保存布局、真实槽变在战斗／事务中保留并在安全边界消费、宏修订不被提前读取吞掉、退出取消排队回调。`actionbar_snapshot_reads.lua` 检查单次观察只克隆一次旧布局；`macro_observation_changes.lua` 检查相同宏通知不复制布局，真实编辑和删除保留最新备份。`core_spec.lua` 检查专精未就绪及原生返回字段保留。`reminders.lua` 和 `motion.lua` 分别回放候选变更与入战中断动效。

本轮全仓审计的范围、修复与验证记录见 [2026-10-31 审计结果](audit-20261031.md)。

`catalog_loading.lua` 使用生产 Catalog 与实际圣骑士数据包，复现 `LoadAddOn` 返回 `false/nil, DISABLED` 后出现两个不可用英雄按钮的路径，核对仅启用当前角色的当前职业包、原生加载重试一次、8 个大秘境推荐恢复及成功缓存。它同时检查持续失败、缺包、旧分片和战斗延后。`ui_smoke.lua data-errors` 检查真实加载失败原因的空态、个人方案可用及后续成功加载。
