local _, A = ...
local T = {}
A.Talents = T
T.cache={}; T.order={}
function T:ReadEntries(config)
    local f=self:Frame(); if not f then return nil end
    local tree=C_ClassTalents.GetTraitTreeForSpec(A:GetSpec())
    local stream=ExportUtil.MakeExportDataStream()
    f:WriteLoadoutHeader(stream,C_Traits.GetLoadoutSerializationVersion(),A:GetSpec(),C_Traits.GetTreeHash(tree))
    f:WriteLoadoutContent(stream,config,tree)
    return self:Entries(stream:GetExportString(),config)
end
function T:Entries(code,config)
    local f=self:Frame(); if not f then return nil end
    local tree=C_ClassTalents.GetTraitTreeForSpec(A:GetSpec())
    local stream=ExportUtil.MakeImportDataStream(code)
    local valid=f:ReadLoadoutHeader(stream); if not valid then return nil end
    local content=f:ReadLoadoutContent(stream,tree)
    return f:ConvertToImportLoadoutEntryInfo(config or C_ClassTalents.GetActiveConfigID(),tree,content)
end
function T:Matches(config,expected)
    local actual=self:ReadEntries(config)
    if not actual then return false,{kind="unavailable",config=config} end
    -- Saved loadouts store purchased choices. Derived granted ranks can be absent
    -- until activated; do not reject an otherwise identical saved loadout for that.
    -- The active config is still checked in full before declaring success.
    local saved=config~=C_ClassTalents.GetActiveConfigID()
    local nodes={}
    local function node(id)
        if not nodes[id] then nodes[id]=C_Traits.GetNodeInfo(config,id) end
        return nodes[id]
    end
    local function effective(entries)
        local subtrees={}; local hasSelection=false
        for _,e in ipairs(entries) do
            local n=node(e.nodeID)
            if n and n.type==Enum.TraitNodeType.SubTreeSelection and (e.ranksPurchased or 0)+(e.ranksGranted or 0)>0 then
                local info=C_Traits.GetEntryInfo(config,e.selectionEntryID)
                if info and info.subTreeID then subtrees[info.subTreeID]=true;hasSelection=true end
            end
        end
        local map={}
        for _,e in ipairs(entries) do
            local purchased=e.ranksPurchased or 0
            local granted=not saved and (e.ranksGranted or 0) or 0
            local n=node(e.nodeID)
            -- Native exports can contain a free root from the OTHER hero tree.
            -- Resolve the selected subtree from this snapshot's choice entries,
            -- not the current UI preview. It is not an effective talent mismatch.
            if purchased==0 and granted>0 and hasSelection and n and n.subTreeID and not subtrees[n.subTreeID] then granted=0 end
            if purchased+granted>0 then map[e.nodeID..":"..e.selectionEntryID]=purchased+granted end
        end
        return map
    end
    local map=effective(expected)
    for key,count in pairs(effective(actual)) do
        if (map[key] or 0)~=count then
            local id,entry=key:match("^(%d+):(%d+)$")
            return false,{kind="entry",node=tonumber(id),entry=tonumber(entry),expected=map[key] or 0,actual=count}
        end
        map[key]=nil
    end
    local missing,ranks=next(map)
    if missing then return false,{kind="missing",key=missing,expected=ranks,actual=0} end
    return true
end
-- Stage a replacement in the working tree without creating another saved loadout.
-- Caller owns the transaction and must roll back a failed/partial stage.
function T:StageEntries(config,entries)
    if InCombatLockdown() or not entries or #entries>512 then return nil,"APPLY_UNAVAILABLE" end
    local tree=C_ClassTalents.GetTraitTreeForSpec(A:GetSpec())
    if not tree or not C_Traits.ResetTree(config,tree) then return nil,"APPLY_FAILED" end
    local targets,order={},{}
    for _,entry in ipairs(entries) do
        local id=entry.nodeID
        local target=targets[id]
        if not target then target={id=id,ranks=0,granted=0};targets[id]=target;order[#order+1]=target end
        target.ranks=target.ranks+(entry.ranksPurchased or 0)
        target.granted=target.granted+(entry.ranksGranted or 0)
        if (entry.ranksPurchased or 0)+(entry.ranksGranted or 0)>0 then target.selection=entry.selectionEntryID end
    end
    table.sort(order,function(a,b)
        local na,nb=C_Traits.GetNodeInfo(config,a.id),C_Traits.GetNodeInfo(config,b.id)
        local ay,by=na and na.posY or 0,nb and nb.posY or 0
        if ay~=by then return ay<by end
        return a.id<b.id
    end)
    local budget=512
    for pass=1,16 do
        local progress=false
        for _,target in ipairs(order) do
            local info=C_Traits.GetNodeInfo(config,target.id)
            if info and info.isAvailable and info.isVisible then
                local selection=info.type==Enum.TraitNodeType.Selection or info.type==Enum.TraitNodeType.SubTreeSelection
                if selection and target.selection and (not info.activeEntry or info.activeEntry.entryID~=target.selection) then
                    if C_Traits.SetSelection(config,target.id,target.selection) then progress=true end
                    info=C_Traits.GetNodeInfo(config,target.id)
                end
                local ranks=info and info.ranksPurchased or 0
                while ranks<target.ranks and budget>0 and C_Traits.CanPurchaseRank(config,target.id,target.selection) do
                    budget=budget-1
                    if not C_Traits.PurchaseRank(config,target.id) then break end
                    progress=true;info=C_Traits.GetNodeInfo(config,target.id)
                    local updated=info and info.ranksPurchased or ranks
                    if updated<=ranks then break end
                    ranks=updated
                end
            end
        end
        local matches,difference=self:Matches(config,entries)
        if matches then return true end
        if not progress or budget==0 then return nil,"STAGED_MISMATCH",difference end
    end
    return nil,"STAGED_MISMATCH"
end
function T:Code(build)
    if not build then return nil,"BAD_CODE" end
    if build.code then return build.code end
    local packed=type(build.nodes)=="string"
    if build.source~="builtin" or (not packed and type(build.nodes)~="table") then return nil,"BAD_CODE" end
    if packed and build.nodes:gsub("%d+:%d+;","")~="" then return nil,"BAD_CODE" end
    local version=GetBuildInfo()
    if not version or version:sub(1,#build.patch)~=build.patch then return nil,"TREE_CHANGED" end
    if build.specIndex~=C_SpecializationInfo.GetSpecialization() then return nil,"WRONG_SPEC" end
    local key=build.id..":"..build.version
    if self.cache[key] then return self.cache[key] end
    local f,err=self:Frame(); if not f then return nil,err end
    local ok,code=pcall(function()
        local ranks,nodeCount={},0
        if packed then
            for entry,rank in build.nodes:gmatch("(%d+):(%d+);") do
                ranks[tonumber(entry)]=tonumber(rank);nodeCount=nodeCount+1
            end
        else
            for _,v in ipairs(build.nodes) do ranks[v[1]]=v[2];nodeCount=nodeCount+1 end
        end
        local tree=C_ClassTalents.GetTraitTreeForSpec(A:GetSpec())
        local config=C_ClassTalents.GetActiveConfigID()
        local stream=ExportUtil.MakeExportDataStream()
        f:WriteLoadoutHeader(stream,C_Traits.GetLoadoutSerializationVersion(),A:GetSpec(),C_Traits.GetTreeHash(tree))
        local matched=0
        for _,id in ipairs(C_Traits.GetTreeNodes(tree)) do
            local node=C_Traits.GetNodeInfo(config,id)
            local purchased,index,hits=0,1,0
            for i,entry in ipairs(node.entryIDs or {}) do
                if ranks[entry] then purchased=purchased+ranks[entry]; index=i; hits=hits+1; matched=matched+1 end
            end
            local choice=node.type==Enum.TraitNodeType.Selection or node.type==Enum.TraitNodeType.SubTreeSelection
            if (choice and hits>1) or purchased>node.maxRanks then error("incompatible node") end
            local granted=node.activeRank-node.ranksPurchased>0 and not node.subTreeID
            if granted and purchased>0 then purchased=math.max(0,purchased-1) end
            local selected=purchased>0 or granted
            stream:AddValue(1,selected and 1 or 0)
            if selected then
                stream:AddValue(1,purchased>0 and 1 or 0)
                if purchased>0 then
                    stream:AddValue(1,purchased~=node.maxRanks and 1 or 0)
                    if purchased~=node.maxRanks then stream:AddValue(6,purchased) end
                    stream:AddValue(1,choice and 1 or 0)
                    if choice then if index>4 then error("choice overflow") end; stream:AddValue(2,index-1) end
                end
            end
        end
        if matched~=nodeCount then error("unknown entries") end
        return stream:GetExportString()
    end)
    if not ok then return nil,"TREE_CHANGED" end
    local valid,why=self:Validate(code); if not valid then return nil,why end
    self.order[#self.order+1]=key; self.cache[key]=code
    if #self.order>16 then self.cache[table.remove(self.order,1)]=nil end
    return code
end
function T:Diff(build)
    local code,err=self:Code(build); if not code then return nil,err end
    local target=self:Entries(code); local current=self:ReadEntries(C_ClassTalents.GetActiveConfigID())
    if not target or not current then return nil,"NOT_READY" end
    local map={}; for _,v in ipairs(current) do map[v.selectionEntryID]=(v.ranksPurchased or 0)+(v.ranksGranted or 0) end
    local changes={}
    for _,v in ipairs(target) do
        local count=(v.ranksPurchased or 0)+(v.ranksGranted or 0)
        if map[v.selectionEntryID]~=count then
            local e=C_Traits.GetEntryInfo(C_ClassTalents.GetActiveConfigID(),v.selectionEntryID)
            local d=e and C_Traits.GetDefinitionInfo(e.definitionID)
            local name=d and (d.overrideName or (d.spellID and C_Spell.GetSpellName(d.spellID)))
            changes[#changes+1]=(name or tostring(v.selectionEntryID)).." ("..count..")"
        end
        map[v.selectionEntryID]=nil
    end
    local removed=0; for _ in pairs(map) do removed=removed+1 end
    return changes,removed
end
function T:Frame()
    if InCombatLockdown() then return nil,"COMBAT" end
    if not A:GetSpec() then return nil,"NO_SPEC" end
    if not PlayerSpellsFrame then
        local ok=pcall(C_AddOns.LoadAddOn,"Blizzard_PlayerSpells")
        if not ok then return nil,"NOT_READY" end
    end
    local f=PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    if not f or not f.ReadLoadoutHeader or not ExportUtil then return nil,"NOT_READY" end
    return f
end
function T:Validate(code)
    if type(code)~="string" then return nil,"BAD_CODE" end
    code=code:gsub("%s","")
    if #code<24 or #code>16384 or code:find("[^A-Za-z0-9+/=]") then return nil,"BAD_CODE" end
    local f,err=self:Frame(); if not f then return nil,err end
    local spec=A:GetSpec()
    local treeID=C_ClassTalents.GetTraitTreeForSpec(spec)
    if not treeID then return nil,"NOT_READY" end
    local ok,result=pcall(function()
        local stream=ExportUtil.MakeImportDataStream(code)
        local extract=stream.ExtractValue
        local consumed=0
        local available=stream:GetNumberOfBits()
        stream.ExtractValue=function(s,width)
            if consumed+width>available then error("truncated talent string") end
            consumed=consumed+width
            return extract(s,width)
        end
        local valid,version,importSpec,hash=f:ReadLoadoutHeader(stream)
        if not valid or version~=C_Traits.GetLoadoutSerializationVersion() then return "BAD_CODE" end
        if importSpec~=spec then return "WRONG_SPEC" end
        if not f:IsHashEmpty(hash) and not f:HashEquals(hash,C_Traits.GetTreeHash(treeID)) then return "TREE_CHANGED" end
        local content=f:ReadLoadoutContent(stream,treeID)
        if type(content)~="table" or #content==0 then return "BAD_CODE" end
        local entries=f:ConvertToImportLoadoutEntryInfo(C_ClassTalents.GetActiveConfigID(),treeID,content)
        if not entries or #entries==0 then return "BAD_CODE" end
        return true
    end)
    if not ok then return nil,"BAD_CODE" end
    if result~=true then return nil,result end
    return code,spec
end
function T:Export(includeStaged)
    local f,err=self:Frame(); if not f then return nil,err end
    local config=C_ClassTalents.GetActiveConfigID()
    if not config then return nil,"NOT_READY" end
    if not includeStaged and C_Traits.ConfigHasStagedChanges and C_Traits.ConfigHasStagedChanges(config) then return nil,"PENDING" end
    local ok,code=pcall(function()
        local spec=A:GetSpec()
        local tree=C_ClassTalents.GetTraitTreeForSpec(spec)
        local stream=ExportUtil.MakeExportDataStream()
        f:WriteLoadoutHeader(stream,C_Traits.GetLoadoutSerializationVersion(),spec,C_Traits.GetTreeHash(tree))
        f:WriteLoadoutContent(stream,config,tree)
        return stream:GetExportString()
    end)
    if not ok or not code then return nil,"NOT_READY" end
    return self:Validate(code)
end
function T:OpenNative()
    if InCombatLockdown() then return nil,"COMBAT" end
    if not PlayerSpellsUtil or not PlayerSpellsUtil.OpenToClassTalentsTab then return nil,"NOT_READY" end
    -- Native first-show selects the remembered loadout by loading it. Opening
    -- our browser must preserve the current working tree (including a draft).
    -- Seed only an empty selection with the native skipLoad path.
    local frame=PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame
    local saved=C_ClassTalents.GetLastSelectedSavedConfigID(A:GetSpec())
    if frame and frame.LoadSystem and frame.SetSelectedSavedConfigID and saved
        and not frame.LoadSystem:GetSelectionID()
        and frame.LoadSystem:IsSelectionIDValid(saved)
        and not C_ClassTalents.GetStarterBuildActive() then
        frame:SetSelectedSavedConfigID(saved,false,true)
    end
    local ok=pcall(PlayerSpellsUtil.OpenToClassTalentsTab)
    if not ok then return nil,"NOT_READY" end
    return true
end
function T:PrepareImport(build)
    if not build then return nil,"BAD_CODE" end
    local code,err=self:Validate(build.code)
    if not code then return nil,err end
    local config=C_ClassTalents.GetActiveConfigID()
    if config and C_Traits.ConfigHasStagedChanges and C_Traits.ConfigHasStagedChanges(config) then return nil,"PENDING" end
    if not C_ClassTalents.CanCreateNewConfig or not C_ClassTalents.CanCreateNewConfig() then return nil,"NATIVE_LIMIT" end
    local opened,openErr=self:OpenNative(); if not opened then return nil,openErr end
    local d=ClassTalentLoadoutImportDialog
    if not d or not d.ShowDialog or not d.ImportControl or not d.NameControl then return nil,"APPLY_UNAVAILABLE" end
    -- Only populate the game's new-loadout dialog. Never call OnAccept, ImportLoadout,
    -- CommitConfig, ResetTree, SetAction, or manipulate any existing config.
    d:ShowDialog()
    d.ImportControl:GetEditBox():SetText(code)
    d.NameControl:GetEditBox():SetText(build.name)
    d:UpdateAcceptButtonEnabledState()
    return true
end
