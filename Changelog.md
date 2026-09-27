# 更新记录 / Changelog

## 1.0.2 · 2026-09-27

- 修复同名宏内容或账号／角色范围不同时阻止天赋切换的问题。
- 从动作条读取确切宏编号，恢复时核对内容与归属，支持宏索引重排。

## 1.0.1 · 2026-09-27

- 保存和导入按钮改用红底白字，明确区分正常、悬停、按下和禁用状态。
- 场景关联页的保存按钮同步调整。

## 1.0.0 · 2026-09-27

荔枝天赋首版，面向正式服 12.1。

- **按场景选天赋**：原生天赋页旁显示大秘境、团本和个人方案；双击应用，菜单查看来源和复制字符串。
- **WCL 推荐**：随包提供 2026-09-26 采集的 1,815 条组合，覆盖 13 职业、40 专精，团本区分英雄／史诗。
- **个人方案**：导入、保存当前、编辑名称／字符串／图标，并关联多个副本或首领。
- **动作条管理**：每专精复用一个原生方案，支持默认布局和独立布局；原生栏位不足时停止，不删除其他方案。
- **到场提醒**：内置推荐与个人关联统一提醒，点击才切换，战斗中延后；齿轮设置可关闭。
- **界面**：中文／英文、统一编辑页、场景关联卡片、连续滚动图标网格和减少动态效果。
- **首版修正**：异步配置命名、英雄天赋节点比较、嵌套滚轮路由、重复刷新打断双击；调整关联与更多图标对齐。
- **性能**：职业数据按需加载并去重；列表与图标复用，图标目录关闭后可回收，生产路径不强制 GC。

实机验证以单角色为主；跨副本与首领区域触发、其他职业、重新登录、完整帧时间和 taint 仍待覆盖。详见 [性能记录](PERFORMANCE.md)。

### English

Initial Retail 12.1 release: encounter-based WCL recommendations, personal builds, per-build action bars, one native loadout per specialization and encounter reminders. Includes Chinese/English text, editable encounter associations, a virtualized icon picker and compact class data. The snapshot contains 1,815 builds collected on 2026-09-26. Live coverage is currently limited to one character; broader performance and compatibility validation remains outstanding.
