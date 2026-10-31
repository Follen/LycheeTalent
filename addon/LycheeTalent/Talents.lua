local _, A = ...
local T = {}
A.Talents = T
T.cache={}; T.order={}
-- Only a change token for settled configurations. Draft export semantics are
-- deliberately left to the live node reader and the existing native codec.
function T:StableConfigToken(config)
    if not C_Traits or type(C_Traits.GenerateImportString)~="function" then return end
    local ok,code=pcall(function()
        local active=C_ClassTalents.GetActiveConfigID()
        if not active or C_Traits.ConfigHasStagedChanges(active) or C_Traits.GetLoadoutSerializationVersion()~=2 then return end
        local value=C_Traits.GenerateImportString(config)
        if issecretvalue and issecretvalue(value) then return end
        if type(value)~="string" or #value<24 or #value>16384 or value:find("[^A-Za-z0-9+/=]") then return end
        local f=self:Frame();if not f then return end
        local stream=ExportUtil.MakeImportDataStream(value)
        local valid,version,spec,hash=f:ReadLoadoutHeader(stream)
        if not valid or version~=2 or spec~=A:GetSpec() or f:IsHashEmpty(hash) then return end
        local tree=C_ClassTalents.GetTraitTreeForSpec(spec)
        if not tree or not f:HashEquals(hash,C_Traits.GetTreeHash(tree)) then return end
        return value
    end)
    if ok then return code end
end
function T:ReadEntries(config,withMetadata)
    local f=self:Frame(); if not f then return nil end
    local tree=C_ClassTalents.GetTraitTreeForSpec(A:GetSpec())
    -- These flags match serialization v2; newer formats keep the native codec.
    if type(f.CreateImportLoadoutEntryInfoFromSingleNode)=="function"
        and type(f.CreateImportLoadoutEntryInfoFromTieredNode)=="function"
        and type(f.GetActiveEntryIndex)=="function"
        and C_Traits.GetLoadoutSerializationVersion()==2 then
        -- Mirror native WriteLoadoutContent -> ReadLoadoutContent flags, then
        -- let Blizzard allocate entries (especially Tiered per-entry ranks).
        -- No serialized string or second GetNodeInfo pass is needed.
        local nodes=C_Traits.GetTreeNodes(tree)
        if not nodes then return nil end
        local results={}
        local metadata=withMetadata and {types={},subtrees={}} or nil
        for _,id in ipairs(nodes) do
            local node=C_Traits.GetNodeInfo(config,id)
            if not node then return nil end -- never return a partial tree as complete
            if metadata then metadata.types[id]=node.type;metadata.subtrees[id]=node.subTreeID end
            local purchased=node.ranksPurchased>0
            local selected=node.activeRank-node.ranksPurchased>0 or purchased
            if selected then
                local indexInfo={isNodeSelected=true,isNodeGranted=not purchased,
                    isPartiallyRanked=false,partialRanksPurchased=0,isChoiceNode=false,choiceNodeSelection=1}
                if purchased then
                    indexInfo.isPartiallyRanked=node.ranksPurchased~=node.maxRanks
                    if indexInfo.isPartiallyRanked then indexInfo.partialRanksPurchased=node.ranksPurchased end
                    indexInfo.isChoiceNode=node.type==Enum.TraitNodeType.Selection or node.type==Enum.TraitNodeType.SubTreeSelection
                    if indexInfo.isChoiceNode then
                        local selection=f:GetActiveEntryIndex(node)
                        if selection<=0 or selection>4 then
                            error("Error exporting tree node "..node.ID..". The active choice node entry index ("..selection..") is out of bounds. ")
                        end
                        indexInfo.choiceNodeSelection=selection
                    end
                end
                if node.type==Enum.TraitNodeType.Tiered then
                    f:CreateImportLoadoutEntryInfoFromTieredNode(results,config,node,indexInfo)
                else f:CreateImportLoadoutEntryInfoFromSingleNode(results,config,node,indexInfo) end
            end
        end
        return results,metadata
    end
    -- Older/custom native frames can keep their existing roundtrip contract.
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
    local actual,metadata=self:ReadEntries(config,true)
    if not actual then return false,{kind="unavailable",config=config} end
    -- Saved loadouts store purchased choices. Derived granted ranks can be absent
    -- until activated; do not reject an otherwise identical saved loadout for that.
    -- The active config is still checked in full before declaring success.
    local saved=config~=C_ClassTalents.GetActiveConfigID()
    local nodes={}
    local function node(id)
        -- Only metadata from this call's full native scan; never cached ranks.
        if metadata and metadata.types[id]~=nil then return metadata.types[id],metadata.subtrees[id] end
        if not nodes[id] then nodes[id]=C_Traits.GetNodeInfo(config,id) end
        local info=nodes[id]
        if info then return info.type,info.subTreeID end
    end
    local function effective(entries)
        local subtrees={}; local hasSelection=false
        for _,e in ipairs(entries) do
            local kind=node(e.nodeID)
            if kind==Enum.TraitNodeType.SubTreeSelection and (e.ranksPurchased or 0)+(e.ranksGranted or 0)>0 then
                local info=C_Traits.GetEntryInfo(config,e.selectionEntryID)
                if info and info.subTreeID then subtrees[info.subTreeID]=true;hasSelection=true end
            end
        end
        local map={}
        for _,e in ipairs(entries) do
            local purchased=e.ranksPurchased or 0
            local granted=not saved and (e.ranksGranted or 0) or 0
            local _,subtree=node(e.nodeID)
            -- Native exports can contain a free root from the OTHER hero tree.
            -- Resolve the selected subtree from this snapshot's choice entries,
            -- not the current UI preview. It is not an effective talent mismatch.
            if purchased==0 and granted>0 and hasSelection and subtree and not subtrees[subtree] then granted=0 end
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
    return true,nil,actual
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
        if not target then target={id=id,ranks=0};targets[id]=target;order[#order+1]=target end
        target.ranks=target.ranks+(entry.ranksPurchased or 0)
        if (entry.ranksPurchased or 0)+(entry.ranksGranted or 0)>0 then target.selection=entry.selectionEntryID end
    end
    -- Positions are tree metadata; rank/availability reads below remain live.
    -- Native GetNodeInfo allocates its complete nested table on each call.
    for _,target in ipairs(order) do
        local node=C_Traits.GetNodeInfo(config,target.id)
        target.y=node and node.posY or 0
    end
    table.sort(order,function(a,b)
        if a.y~=b.y then return a.y<b.y end
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
