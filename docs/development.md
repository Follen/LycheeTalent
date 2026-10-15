# 开发与验证

生产文件在 `addon/`，包含主包和 13 个按需加载的职业数据包。Lua 5.1、Python 3（采集器使用标准库）、PowerShell 用于本地检查与打包。

产品范围与业务规则见 [product.md](../product.md)，界面与交互见 [Design.md](../Design.md)，模块、数据和应用流程见 [architecture.md](../architecture.md)。本文负责开发操作、检查入口与验证边界。

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

拖动排序与图标选择器的交互见 [UI/UX 设计](../Design.md)。相关检查入口为 `tests/build_order.lua`、`tests/ui_smoke.lua reorder` 及两个图标测试。

## 更新推荐

凭据保存在项目外，支持 `WCL_CLIENT_ID` / `WCL_CLIENT_SECRET` 环境变量，也可向 `tools/wcl/collect.py --credentials` 传入本地文件路径。不要把凭据提交到仓库。原始 SQLite 数据库位于忽略的 `data/private/`。

采集前检查游戏补丁、赛季、场景与观察窗口。不能只改版本标签冒充新数据。`data/publication.json` 记录采集时间及数量；生成的职业分片随源码提交。

采集选择规则（包括奶骑大秘境的固定来源）见 [产品定义](../product.md#推荐数据)。局部刷新与全量采集的时间字段见 [架构说明](../architecture.md#数据采集与发布)。

## 安装与打包

安装脚本 `tools/install.ps1 -AddOnsPath <目标AddOns目录>` 复制并核对文件哈希，不发送游戏输入。打包脚本逐文件校验 ZIP；发布物只包含插件文件及协议、第三方声明。截图、原始诊断、角色资料和采集数据库不进安装包。

单角色已验证原生方案复用及 180 槽动作条往返。跨副本、首领区域触发、跨职业、重新登录、taint 和完整帧时间仍有覆盖边界。性能见 [PERFORMANCE.md](../PERFORMANCE.md)。

## 动作条检查覆盖

动作条的读取时机、保存归属与宏身份处理见 [架构说明](../architecture.md#应用事务与动作条) 和 [天赋应用与动作条](talent-application.md)。

`actionbar_capture_events.lua` 覆盖 500 次独立刷新、同步／延迟通知、同名宏交换和删除后在切换时保存、重载及退出时保留用户光标。`macro_identity.lua` 覆盖普通宏直接读取、带子类型宏的准确编号读取、61 槽旧占位符恢复及缺失宏报错。`single_config.lua` 覆盖单配置复用、共用／独立布局往返、重载后保存、读取前显示进度和首次读取失败。以上均为离线 API 替身；本次按用户要求不做实机验证，第 61 槽的实际返回值尚未取得。
