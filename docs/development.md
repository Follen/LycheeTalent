# 开发与验证

生产文件在 `addon/`，包含主包和 13 个按需加载的职业数据包。Lua 5.1、Python 3（采集器使用标准库）、PowerShell 用于本地检查与打包。

```powershell
lua tests/run.lua
lua tests/ui_smoke.lua
lua tests/ui_smoke.lua same-build-refresh
lua tests/ui_smoke.lua pending-prompt
lua tests/single_config.lua
lua tests/actionbar_profiles.lua
lua tests/actionbar_restore.lua
lua tests/actionbar_edgecases.lua
lua tests/actionbar_edgecases.lua override
lua tests/macro_identity.lua
lua tests/inactive_hero.lua
lua tests/native_open.lua
lua tests/reminders.lua
lua tests/catalog_business.lua
lua tests/motion.lua
lua tests/icons.lua
lua tests/icon_provider_lifecycle.lua
lua tests/data_memory.lua MAGE 500
python -m unittest discover -s tests -p 'test_*.py'
powershell -File tools/package.ps1
```

`test_data_publication.py` 的完整等价性比较需要本地采集数据库；没有数据库会明确 skip，其他纯逻辑测试无需凭据。离线替身测试不能证明原生 API、taint 或真实帧时间。

## 更新推荐

凭据保存在项目外，支持 `WCL_CLIENT_ID` / `WCL_CLIENT_SECRET` 环境变量，也可向 `tools/wcl/collect.py --credentials` 传入本地文件路径。不要把凭据提交到仓库。原始 SQLite 数据库位于忽略的 `data/private/`。

采集前检查游戏补丁、赛季、场景与观察窗口。不能只改版本标签冒充新数据。`data/publication.json` 记录采集时间及数量；生成的职业分片随源码提交。

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
