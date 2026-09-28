local _, A = ...
local en = {
    VERSION="Version",AUTHOR_WECHAT="Author on WeChat",WECHAT_SUPPORT="WeChat support",SCAN_WECHAT="Scan with WeChat",COPY_LINK_HELP="Ctrl+C to copy · Esc to close",
    CONTEXTS_EMPTY_HELP="Choose where to use this build",
    TOOLTIP_CONTEXTS="%d linked encounters",
    CHOOSE_CONTEXTS="Link dungeons / bosses", SELECTED_CONTEXTS="Linked to %d encounters", NEW_BUILD="New build",
    LINKED_SHORT="Linked", MORE_CONTEXTS="%d more encounters", GLOBAL_REMINDERS_OFF="Reminders globally disabled", BINDINGS_HINT="Edit this build to change linked encounters.",
    SETTINGS="Settings", GLOBAL_REMINDERS="Talent reminders", GLOBAL_REMINDERS_HELP="WCL recommendations and your linked builds. Switch only when you choose.", LYCHEE_RECOMMENDATION="Lychee recommended",
    SCENE_REMINDERS="Dungeon / boss reminders", REMINDER_ON="Arrival reminder · On", REMINDER_OFF="Arrival reminder · Off",
    REMINDER_TITLE="Talent reminder", REMINDER_SWITCH="Switch", NOT_NOW="Not now", REMINDER_CHANGED="The encounter or build changed.",
    BARS_INVALID="The saved action bar layout is incomplete.", BARS_MISSING="No saved action bar layout is available.",
    BARS_CONTEXT="The active loadout or action bar context changed.", BARS_CURSOR="Place the item on your cursor before switching builds.",
    BARS_SECRET="Action bar data is unavailable right now.", BARS_MACRO="The recorded macro slot is empty. Place a macro there or update your action bar layout.",
    BARS_MACRO_READ="A macro on the current action bars could not be read. Try again with an empty cursor, out of combat.",
    BARS_UNAVAILABLE="Some actions cannot be restored right now. Your layout records have been kept.",
    BARS_UNSUPPORTED="This action type cannot be restored. Your layout records have been kept.",
    BARS_RESTORE="Action bar restoration failed. Your layout records have been kept.",

    COPY_WCL="Copy WCL link", WCL_LEVEL="WCL · +%d", WCL_RECORD="Recorded · %s",
    WCL_SHIFT_HINT="Hold Shift for source", WCL_RELEASE_HINT="Release Shift to close · Esc to dismiss", WCL_COPY_HINT="Ctrl+C to copy · Esc to close",
    ICON="Icon", CHOOSE_ICON="Choose icon", ICON_COMMON="Common", ICON_SPELL="Spells", ICON_ITEM="Items",
    TITLE="Lychee Talent", SUBTITLE="Choose talents for your next encounter.",
    MYTHIC="Mythic+", RAID="Raid", MINE="My builds", ALL="All", BUILTIN="Recommended", USER="Personal",
    SEARCH="Search builds, dungeons or bosses", SEARCH_SCOPE="Current specialization · all scenarios",
    IMPORT="Import", SAVE_CURRENT="Save current", NAME="Build name", CODE="Talent import string",
    SCENE="Scenario", TARGET="Dungeon / boss (optional)", SAVE="Save build", CANCEL="Cancel", CLOSE="Close",
    EMPTY="A clear space for your next build", EMPTY_HELP="Import a talent string or save your current talents to begin.",
    EMPTY_RECOMMENDED="Recommendations are not published yet", EMPTY_RECOMMENDED_HELP="WCL data will appear here after collection and validation. Your personal builds are ready to use.",
    NO_MATCH="No matching builds", NO_MATCH_HELP="Try a build, dungeon or boss name, or change the source filter.",
    SELECT="Select a build", SELECT_HELP="Choose a build to inspect its scenario and talent string.",
    DETAILS="BUILD DETAILS", SOURCE="Source", SPEC="Specialization", UPDATED="Last saved",
    EXPORT="Copy string", DELETE="Delete", UNDO="Undo delete", APPLY="Apply build", FAVORITE="Favorite", UNFAVORITE="Unfavorite",
    IMPORT_TITLE="Import talents", IMPORT_HELP="Saving a build does not change your current talents.",
    NAME_OPTIONAL="Build name (optional)", IMPORT_ACTION="Import", DEFAULT_NAME="%s · Build %d",
    CODE_HELP="Only talent strings for your current specialization can be saved.",
    SAVED="Build saved. Your active talents are unchanged.", DELETED="Build deleted.", RESTORED="Build restored.",
    BAD_NAME="Enter a build name.", BAD_CODE="This talent string is incomplete or invalid.", WRONG_SPEC="This string belongs to another specialization.",
    TREE_CHANGED="This string uses a different talent tree version.", NOT_READY="Open the game talent panel once, then try again.",
    COMBAT="This action is unavailable in combat.", CAPACITY="Your library is full. Export and remove an old build first.",
    EXPORT_HELP="Press Ctrl+C to copy. Import into a new game loadout to preserve your existing one.",
    APPLY_UNAVAILABLE="Safe native-loadout switching is not available in this client. Export is available.",
    APPLYING="Preparing a separate game loadout…", APPLIED="Native loadout created. Review and apply in the talent panel.",
    APPLY_FAILED="The game did not confirm the operation. Your saved build is unchanged.",
    CURRENT="Current talents", PERSONAL_NOTE="Saved by you. Recommendation updates will never overwrite this build.",
    FOOTER="Personal library · current specialization", PREVIEW="First version", SETTINGS="Settings",
    MOTION="Reduced motion", NATIVE="Open talents", PENDING="Finish or undo your pending talent edits first.",
    PENDING_CONFIRM="You have unapplied talent edits. Discard them and apply %s?",
    PENDING_REPLACE="Discard and apply", PENDING_CHANGED="Talent edits changed. Double-click the build again to review.",
    ROLLBACK_FAILED="The game could not discard the pending edits. No new build was applied.",
    NATIVE_LIMIT="No free native loadout slot. Manage your game loadouts first.",
    NATIVE_NOTE="Creates a new native loadout. Review the game's shared/independent action bar option before applying.",
    PREPARED="Loadout prepared in the game talent panel. Confirm there to apply.",
    NO_SPEC="Choose a specialization before managing builds.", NEW_COPY="A new native loadout will be created; existing loadouts are not selected for overwrite.",
    SCHEMA="Saved data comes from a newer version. Library editing is disabled.",
    APPLY_SUCCESS="Talents applied and action bar mode verified.", APPLY_INTERRUPTED="Switch interrupted. Recovery information has been retained.",
    APPLY_TIMEOUT="The game did not confirm the switch in time. Check current talents before retrying.",
    APPLY_BUSY="A talent switch is already in progress.", ACTIONBAR_FAILED="The action bar mode could not be verified.",
    ORIGINAL_CHANGED="The original loadout changed during this operation. Recovery information is available.",
    STARTER_ACTIVE="Turn off the game's starter build before using managed loadouts.",
    RESTORE="Return to previous build", NO_RECOVERY="No recovery build is available for this specialization.", RESTORE_REQUESTED="Return requested. Verify the result in the game talent panel.",
    HIGHEST="Highest key with talents", POPULAR="Common logged build", RANKED="Boss ranking reference", MYTHIC_RAID="Mythic", HEROIC_RAID="Heroic",
    FORK="Copy to my builds", EDIT="Edit build", INDEPENDENT="Independent action bars", SHARED="Shared action bars",
    ALL_TARGETS="All encounters", SCENARIOS="Choose an encounter", SOURCE_LINK="WCL source", DIFF="Compare talents", DIFF_TITLE="Changes from current talents",
    DIFF_REMOVED="Entries removed: %d", DIFF_EMPTY="This build matches your current talents.", SAMPLE="%d usable logs · %s", EVIDENCE="Collected %s · %s",
    BUILTIN_NOTE="Read-only recommendation. Copy it to your builds to make changes.", MOTION_ON="Motion: on", MOTION_OFF="Motion: reduced",
    BACK="Back", RECOVERY_AVAILABLE="A previous talent switch needs review. Recovery information is available.",
    METRIC_KEY="key level", METRIC_DPS="damage", METRIC_HPS="healing",
}
local zh = {
    VERSION="版本",AUTHOR_WECHAT="作者微信",WECHAT_SUPPORT="微信赞赏",SCAN_WECHAT="使用微信扫一扫",COPY_LINK_HELP="Ctrl+C 复制 · Esc 关闭",
    CONTEXTS_EMPTY_HELP="选择适用副本 / 首领",
    TOOLTIP_CONTEXTS="关联场景 · %d",
    CHOOSE_CONTEXTS="关联场景", SELECTED_CONTEXTS="已关联 %d 个场景", NEW_BUILD="新方案",
    LINKED_SHORT="关联", MORE_CONTEXTS="另有 %d 个场景", GLOBAL_REMINDERS_OFF="全局提醒已关闭", BINDINGS_HINT="编辑方案可调整关联场景。",
    GLOBAL_REMINDERS="天赋切换提醒", GLOBAL_REMINDERS_HELP="提醒内置 WCL 和已关联的个人方案，点击后才切换。", LYCHEE_RECOMMENDATION="荔枝推荐天赋",
    SCENE_REMINDERS="副本 / 首领提醒", REMINDER_ON="到达时提醒 · 开启", REMINDER_OFF="到达时提醒 · 关闭",
    REMINDER_TITLE="天赋提醒", REMINDER_SWITCH="切换", NOT_NOW="暂不切换", REMINDER_CHANGED="场景或方案已发生变化。",
    BARS_INVALID="保存的动作条布局不完整。", BARS_MISSING="没有可用的动作条布局记录。",
    BARS_CONTEXT="当前天赋或动作条状态发生了变化。", BARS_CURSOR="请先放下鼠标上的物品或技能，再切换方案。",
    BARS_SECRET="当前无法读取动作条信息。", BARS_MACRO="记录的宏位置已空，请在原位置放入宏，或调整动作条布局。",
    BARS_MACRO_READ="当前动作条上的宏暂时无法读取，请脱战并放下鼠标上的物品或技能后重试。",
    BARS_UNAVAILABLE="部分技能或物品暂时无法恢复，已保留布局记录。",
    BARS_UNSUPPORTED="暂不支持恢复这种动作类型，已保留布局记录。",
    BARS_RESTORE="动作条恢复未完成，已保留布局记录。",
    COPY_WCL="复制 WCL 链接", WCL_LEVEL="WCL · %d 层", WCL_RECORD="记录时间 · %s",
    WCL_SHIFT_HINT="按住 Shift 查看来源", WCL_RELEASE_HINT="松开 Shift 收起 · Esc 关闭", WCL_COPY_HINT="Ctrl+C 复制 · Esc 关闭",
    ICON="图标", CHOOSE_ICON="选择图标", ICON_COMMON="常用", ICON_SPELL="法术", ICON_ITEM="物品",
    TITLE="荔枝天赋", SUBTITLE="为下一场挑战，选好天赋。", MYTHIC="大秘境", RAID="团本", MINE="我的方案",
    ALL="全部", BUILTIN="内置推荐", USER="我的方案", SEARCH="搜索方案、副本或首领", SEARCH_SCOPE="当前专精 · 全部场景",
    IMPORT="导入方案", SAVE_CURRENT="保存当前", NAME="方案名称", CODE="天赋字符串", SCENE="适用场景", TARGET="副本 / 首领（选填）",
    SAVE="保存方案", CANCEL="取消", CLOSE="关闭", EMPTY="准备好你的第一套天赋", EMPTY_HELP="导入一段天赋字符串，或保存当前加点，开始建立你的方案库。",
    EMPTY_RECOMMENDED="内置推荐尚未发布", EMPTY_RECOMMENDED_HELP="WCL 数据完成采集与校验后会出现在这里。你现在可以使用自己的方案。",
    NO_MATCH="没有找到相关方案", NO_MATCH_HELP="试试方案名、副本名或首领名，也可以切换来源筛选。",
    SELECT="选择一套天赋方案", SELECT_HELP="在左侧选择方案，查看场景与天赋字符串。", DETAILS="方案详情", SOURCE="方案来源", SPEC="专精", UPDATED="保存时间",
    EXPORT="复制字符串", DELETE="删除", UNDO="撤销删除", APPLY="应用方案", FAVORITE="收藏", UNFAVORITE="取消收藏",
    IMPORT_TITLE="导入天赋", IMPORT_HELP="保存只会加入方案库，不改变当前天赋。", CODE_HELP="仅保存当前专精且通过校验的天赋字符串。",
    NAME_OPTIONAL="方案名称（选填）", IMPORT_ACTION="导入", DEFAULT_NAME="%s · 方案 %d",
    SAVED="方案已保存，当前天赋未改变。", DELETED="方案已删除。", RESTORED="已恢复方案。",
    BAD_NAME="请输入方案名称。", BAD_CODE="天赋字符串不完整或格式不正确。", WRONG_SPEC="这段天赋字符串属于其他专精。",
    TREE_CHANGED="这段字符串的天赋树版本与当前游戏不一致。", NOT_READY="请先打开一次游戏天赋界面，再重试。",
    COMBAT="战斗中暂时不能进行此操作。", CAPACITY="方案库已满，请先导出并移除不再使用的方案。",
    EXPORT_HELP="按 Ctrl+C 复制。请导入为新的游戏方案，保留已有方案。", APPLY_UNAVAILABLE="当前客户端尚不支持已验证的安全切换，可先复制字符串。",
    APPLYING="正在准备独立的游戏天赋方案……", APPLIED="已创建游戏方案，请在天赋界面检查并应用。", APPLY_FAILED="游戏未确认操作，已保存的方案未改变。",
    CURRENT="当前天赋", PERSONAL_NOTE="由你保存。推荐数据更新不会覆盖这套方案。", FOOTER="个人方案库 · 当前专精", PREVIEW="首版", SETTINGS="设置",
    MOTION="减少动态效果", NATIVE="打开天赋", PENDING="请先应用或撤销游戏界面中尚未提交的天赋修改。",
    PENDING_CONFIRM="当前有未应用的天赋改动。撤销并应用「%s」？",
    PENDING_REPLACE="撤销并应用", PENDING_CHANGED="待提交天赋已改变，请重新双击方案确认。",
    ROLLBACK_FAILED="游戏未能撤销待提交天赋，未切换方案。",
    NATIVE_LIMIT="游戏天赋方案栏位已满，请先管理已有方案。",
    NATIVE_NOTE="新建游戏方案，请在游戏界面检查共享／独立动作条选项后再应用。",
    PREPARED="方案已在游戏天赋界面准备好，请在那里确认应用。", NO_SPEC="请先选择一个专精，再管理天赋方案。",
    NEW_COPY="将新建游戏天赋方案，不选取已有方案进行覆盖。", SCHEMA="存档来自更新版本，已暂停修改方案库。",
    APPLY_SUCCESS="天赋已应用，动作条模式已核对。", APPLY_INTERRUPTED="切换已中断，恢复信息已保留。", APPLY_TIMEOUT="游戏未及时确认切换，请核对当前天赋后再操作。",
    APPLY_BUSY="已有天赋切换正在进行。", ACTIONBAR_FAILED="未能确认动作条模式。", ORIGINAL_CHANGED="操作期间原方案发生变化，已保留恢复信息。",
    STARTER_ACTIVE="请先关闭游戏的入门天赋方案，再使用独立配置。", RESTORE="返回上一个方案", NO_RECOVERY="当前专精没有可恢复的方案。", RESTORE_REQUESTED="已请求返回，请在游戏天赋界面核对结果。",
    HIGHEST="有天赋的最高层", POPULAR="高层常用组合", RANKED="首领排行参考", MYTHIC_RAID="史诗", HEROIC_RAID="英雄",
    FORK="复制到我的方案", EDIT="编辑方案", INDEPENDENT="独立动作条", SHARED="共享动作条", ALL_TARGETS="全部场景", SCENARIOS="选择副本或首领",
    SOURCE_LINK="查看 WCL 来源", DIFF="对比天赋", DIFF_TITLE="与当前天赋的差异", DIFF_REMOVED="移除的天赋项：%d", DIFF_EMPTY="与当前天赋相同。",
    SAMPLE="%d 条有效日志 · %s", EVIDENCE="采集于 %s · %s", BUILTIN_NOTE="内置推荐只读，复制到我的方案后可自由修改。", MOTION_ON="动态效果：开启", MOTION_OFF="动态效果：减少",
    BACK="返回", RECOVERY_AVAILABLE="上次天赋切换需要核对，恢复信息已保留。",
    METRIC_KEY="层数", METRIC_DPS="伤害", METRIC_HPS="治疗",
}
A.L = setmetatable(GetLocale() == "zhCN" and zh or {}, { __index = en })

A.L.BACK=GetLocale()=="zhCN" and "返回方案列表" or "Back to builds"

A.L.MORE=GetLocale()=="zhCN" and "更多" or "More"

A.L.ACTIONBAR_HELP=GetLocale()=="zhCN" and "勾选后，应用天赋时使用独立动作条；取消勾选则共享动作条。此设置会记住，勾选本身不会切换天赋。" or "Checked: applying a build uses independent action bars. Unchecked: shared action bars. This preference is saved; changing it does not apply talents."

A.L.SEARCH_BUTTON=GetLocale()=="zhCN" and "搜索" or "Search"
A.L.APPLYING_SHORT=GetLocale()=="zhCN" and "应用中" or "Applying"

A.L.EXPORT_HELP=GetLocale()=="zhCN" and "按 Ctrl+C 复制" or "Press Ctrl+C to copy"
A.L.NO_MATCH_HELP=GetLocale()=="zhCN" and "试试副本、首领或方案名称。" or "Try a dungeon, boss or build name."
A.L.EMPTY_RECOMMENDED=GetLocale()=="zhCN" and "暂无可用推荐" or "No recommendations available"
A.L.EMPTY_RECOMMENDED_HELP=GetLocale()=="zhCN" and "当前专精在此场景暂无有效数据。" or "No usable data for this specialization and scenario."

A.L.APPLYING=GetLocale()=="zhCN" and "正在应用天赋…" or "Applying talents…"
A.L.APPLY_SUCCESS=GetLocale()=="zhCN" and "天赋已应用" or "Talents applied"

A.L.ACTION_MENU=GetLocale()=="zhCN" and "操作菜单" or "Actions"
A.L.DOUBLE_CLICK_HINT=GetLocale()=="zhCN" and "双击应用天赋" or "Double-click to apply"
A.L.PERSONAL_BUILD_HINT=GetLocale()=="zhCN" and "双击应用 · 拖动排序" or "Double-click: apply · Drag: reorder"

A.L.APPLY_COMBAT=GetLocale()=="zhCN" and "已进入战斗，天赋切换停止。" or "Entered combat. Talent switching stopped."
A.L.APPLY_SPEC_CHANGED=GetLocale()=="zhCN" and "专精已改变，天赋切换停止。" or "Specialization changed. Talent switching stopped."
A.L.STAGED_MISMATCH=GetLocale()=="zhCN" and "待应用天赋与方案不一致，未提交。" or "Staged talents differ from the build. Nothing was committed."
A.L.COMMIT_FAILED=GetLocale()=="zhCN" and "游戏未接受天赋提交，请检查原生天赋面板。" or "The game rejected the commit. Check the native talent panel."
A.L.IMPORTED_MISMATCH=GetLocale()=="zhCN" and "游戏导入的天赋与方案不一致，已停止应用。" or "The imported talents differ from the build. Application stopped."

if GetLocale()=="zhTW" then
    A.L.AUTHOR_WECHAT="作者微信"
    A.L.WECHAT_SUPPORT="微信贊賞"
    A.L.SCAN_WECHAT="使用微信掃一掃"
    A.L.COPY_LINK_HELP="Ctrl+C 複製 · Esc 關閉"
end



A.L.APPLIED_SHORT=GetLocale()=="zhCN" and "已应用" or "Applied"
local zh=GetLocale()=="zhCN"
A.L.TEX_HELP=zh and "将当前专精的天赋迁移到我的方案，保留名称与图标。" or "Copy this spec's builds to My Builds, keeping names and icons."
A.L.TEX_SCOPE=zh and "自动跳过重复方案。分组、PvP 天赋和动作条不迁移。" or "Duplicates are skipped. Groups, PvP talents and action bars stay in Talent EX."
A.L.TEX_UNAVAILABLE=zh and "请先启用 Talent Loadout Ex，并重载界面。" or "Enable Talent Loadout Ex and reload the UI first."
A.L.TEX_EMPTY=zh and "Talent EX 中没有当前专精的方案。" or "Talent EX has no builds for this specialization."
A.L.TEX_REMAINING=zh and "还有 %d 条未处理：%s" or "%d entries remain: %s"
A.L.TEX_ACTION=zh and "导入" or "Import"
A.L.TEX_COUNT=zh and "%s · %d 套方案" or "%s · %d builds"
A.L.TEX_NOT_FOUND=zh and "未检测到 Talent EX" or "Talent EX not detected"
A.L.TEX_INVALID=zh and "%d 套方案格式不兼容" or "%d builds have incompatible formats"
A.L.TEX_DONE=zh and "已导入" or "Imported"
A.L.TEX_UPDATES=zh and "有更新" or "Update"
A.L.TEX_PENDING=zh and "%s · %d 套待导入" or "%s · %d to import"
A.L.TEX_NO_BUILDS=zh and "当前专精没有可导入的方案" or "No builds for this spec"
