# 从入门天赋切换到荔枝天赋

在游戏入门方案启用时选择荔枝方案，复用当前专精已确认归属的原生“荔枝天赋”配置；没有则导入创建一次。原生栏位已满时提示容量不足，不删除或接管其他方案，包括仅名称相同的玩家方案。

即使最后选中的原生配置 ID 仍是荔枝配置，只要入门标记启用，仍执行原生加载。加载结束并核对当前点数与目标原生配置一致后，才调用 `C_ClassTalents.SetStarterBuildActive(false)`；等待入门标记关闭，再应用目标点数与动作条。已有未提交的手动改点继续走原有确认流程。

## 源码依据

通过 LycheeDev 核对 `Gethe/wow-ui-source` 固定提交 `09b9db7948abc9b9648dedaab51eb0cf3ee67b31`：

- `Interface/AddOns/Blizzard_PlayerSpells/ClassTalents/Blizzard_ClassTalentsFrame.lua:1084`，`LoadConfigInternal` 从入门方案加载已保存方案时延后取消入门标记；源码明确说明提前取消会重置待提交改动。
- 同文件 `UnflagStarterBuild` 调用 `SetStarterBuildActive(false)`。无改动的加载立即完成取消标记，异步加载则等提交完成。
- `ClassTalentsDocumentation.lua` 中 `ImportLoadout` 返回成功与错误信息，`SetStarterBuildActive` 返回 `LoadConfigResult`。

## 验证

`lua tests/starter_build.lua` 使用生产 Apply/ActionBars 状态机。修改前首次创建场景被 `STARTER_ACTIVE` 拒绝；修改后覆盖 18 个场景：首次创建、已有配置、记住旧 ID、相同点数、无需改动、Ready 返回、同步/异步取消标记、客户端自动取消标记、同名非自有配置、栏位已满、创建失败、加载失败、取消标记失败/失败事件/超时、战斗、专精改变，以及手动草稿保护。

替身 API 断言取消标记只能在原生加载完成、选中目标配置且没有待提交改动后调用；入门模式中不得直接写入目标点数，玩家配置不被删除或覆盖。`single_config.lua` 保留普通切换与动作条回归覆盖。

以上是固定源码核对和离线验证，未将替身行为视为当前游戏客户端的实机验收。
