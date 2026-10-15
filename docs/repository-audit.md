# 全仓清理审计 · 2026-10-15

## 基线与保护范围

- 审计基线：`794cbe85a325e290959014fd171f82f1885e9232`，main 的 1.0.18 发布提交。
- 前一提交：`7a062dce332778c3e83c03a18882fad53ecb0805`；再前一提交为 `eb57070`。
- 字面最近两提交没有新增或重命名 Markdown。保守保护更早 `eb57070` 新增的 `Design.md`、`architecture.md`、`product.md`，以及 `AGENTS.md`，四份文件与基线逐字节一致。
- 仅使用 `codex/repo-clean`；不修改 main、不合并、不打 tag、不发布、不安装或操作游戏。
- 基线 250 个跟踪文件全部保留，没有删除、移动或重命名 Markdown，也没有删除生产文件、素材、测试 fixture 或历史发布回执。

## 五轮循环

每轮均按“核对候选 → 修改 → 运行相关检查 → 复验”顺序完成；PR 在第五轮结束后才创建。

| 轮次 | 审计与处理 | 证据与复验 |
| --- | --- | --- |
| 1：运行时与加载路径 | 删除 `Talents:Diff`、`Talents:PrepareImport`；移除局部 granted 累加、事务 loadResult/pendingEntries 重复字段、UI shared 镜像、tooltip build 引用和 social anchor 空参数 | 核对所有 TOC、私有命名空间、事件/闭包回调、动态字段和字符串派发。旧两方法无产品入口；现有导入走 Storage，应用走 Apply。保留实际读取的 recovery.pendingEntries。修改前后 29 条 Lua 测试命令均通过 |
| 2：脚本、生成与打包 | 职业包 TOC 不再把版本硬写回 1.0.0，继承主包 Version / Interface；补 3 项测试 | 用当前 13 个职业 TOC 逐字比较生成结果，并验证其他版本、无效元数据。Python 检查与 PowerShell 实际 ZIP 校验通过；两个 PowerShell 脚本语法通过。仓库没有 CI workflow 或 XML 加载入口 |
| 3：文档与保护清单 | 修正 1,815 → 1,856、采集时间、英文 Interface、共用动作条语义、旧包路径；重复介绍改为统一入口；补固定源码与 BitOp 依赖说明 | 与当前 Catalog、publication.json、主包 TOC、发布 metadata 交叉核对；本地文档链接全部有效。历史 Changelog、性能实测及平台回执不改写成新结果；保护文件逐字节不变 |
| 4：回归与删除安全 | 增加 TOC/源码覆盖、协议一致、本地链接、平台 Markdown/HTML 文本一致性检查 | 新测试先暴露英文 HTML 的旧动作条文案，再修复为与 Markdown 一致。18 项 Python 测试：17 通过、1 条数据库依赖测试跳过。29 条正式 Lua 命令和 2 个额外专精变体通过，54 个 Lua 文件通过 Lua 5.1 编译 |
| 5：独立最终复核 | 由未参与前四轮的独立审查者重新检查整个差异、加载/动态入口、生成逻辑、文档与保护清单；记录局部采集发布限制 | 独立复跑 29 条 Lua 命令及 2 个专精变体、18 项 Python（17 通过/1 数据库依赖跳过）、54 个 Lua 编译和 PowerShell ZIP 回归；独立核对 13 职业/40 专精/1,856 条数据，未发现阻断项。所有五轮完成后才创建 PR |

## 保留项与明确边界

- 16 个主包 Lua 全部由 TOC 加载。15 个 TGA 都有真实用途；About 素材由图标/二维码字段动态拼路径，不能按整段路径搜索结果删除。
- `Storage:Undo`、`Macros.Copy`、UI 测试观测字段有回归用途；恢复函数及 SavedVariables 字段涉及已有数据，未把缺少直接 UI 入口当作删除依据。
- 两个 GraphQL 文件是 `client.py --query-file` 的手动 schema/示例输入；场景 JSON 是生成器依赖。SVG 和封面分层图是可编辑素材，原始 DB2/WCL fixture 支持历史测试证据，均保留。
- 采集器的 `--class-name` / `--limit` 只限制采集请求，当前发布阶段仍重写全部数据库职业与全局时间。这里明确记录限制，没有执行采集，也未在清理任务中重写数据发布策略；后续应单独修正发布范围、缓存与时间语义并验证数据库。
- 受保护 `Design.md` 中的“全部/翻页”图标描述与当前“常用/法术/物品”连续滚动界面存在差异；本轮保持文件不变。
- 历史性能预算、实机记录和旧版本数字保留原始日期/口径；本轮没有产生新的游戏内、taint、帧时间或跨职业实机结论。

## 实际验证环境与结果

- Lua 逻辑测试：隔离环境中的 LuaJIT 2.1（Lua 5.1 语义，提供 BitOp），通过 Python Lupa 2.8 调用；每条命令使用独立运行时。
- Lua 语法：Lupa 的原生 Lua 5.1 对所有 54 个跟踪 Lua 文件执行 `loadfile`，未运行客户端 API。
- 固定暴雪源码：`Gethe/wow-ui-source@09b9db7948abc9b9648dedaab51eb0cf3ee67b31` 的 ExportUtil、ClassTalentImportExport、ClassTalentsFrame、IconDataProvider，仅置于忽略目录用于离线测试。
- Python：`python3 -m unittest discover -s tests -p 'test_*.py'`，18 项，17 通过；完整公开 payload 等价性因本地 `data/private/wcl.sqlite3` 不存在而跳过，未声称通过。
- 最终候选 ZIP SHA256：`dc242cf9c04767fee8d583034fe4d717bca69490c845113e5487cbc9500d0a36`；仅验证用，未发布。
- PowerShell 7.6.7：实际执行 `tools/package.ps1` 及 ZIP 回归，验证 14 个包、60 个文件、正斜杠 ZIP 路径和逐文件字节/哈希；没有执行安装脚本。
- 全部 103 个基线 JSON 可解析；Markdown 相对链接、协议副本、TOC 路径、版本一致、`git diff --check` 均通过。
- 未连接或使用 WCL 凭据，未上传平台，未访问用户电脑；没有 CI workflow，因此没有可等待的远端 CI 结论。
