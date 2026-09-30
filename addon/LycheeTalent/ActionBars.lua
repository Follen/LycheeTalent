local _, A = ...
local B = {slotCount=180,profileLimit=1000}
A.ActionBars=B
-- Each specialization has one default and independent profiles per build.
function B:Spec(spec)
    local char=A.Store.character
    if not char or A.Store.readonly or type(spec)~="number" or spec<=0 or spec%1~=0 then return nil end
    char.actionBars=char.actionBars or {version=1,specs={}}
    if type(char.actionBars)~="table" or char.actionBars.version~=1 or type(char.actionBars.specs)~="table" then return nil end
    local specs=char.actionBars.specs
    if not specs[spec] then specs[spec]={profiles={}} end
    if type(specs[spec])~="table" or type(specs[spec].profiles)~="table" then return nil end
    return specs[spec]
end
local function clone(value)
    local out={}
    for k,v in pairs(value) do out[k]=type(v)=="table" and clone(v) or v end
    return out
end
function B:Valid(snapshot,spec)
    if type(snapshot)~="table" or snapshot.version~=1 or snapshot.spec~=spec
        or type(snapshot.slots)~="table" or #snapshot.slots~=self.slotCount then return false end
    for i=1,self.slotCount do
        local entry=snapshot.slots[i]
        if type(entry)~="table" then return false end
        if entry.kind=="unreadableMacro" and entry.id~=i then return false end
        if entry.kind~=nil and (type(entry.kind)~="string" or
            (type(entry.id)~="number" and type(entry.id)~="string")) then return false end
    end
    return true
end
function B:SeedDefault(spec,snapshot,source)
    local state=self:Spec(spec)
    if not state then return nil,"SCHEMA" end
    if state.default then return true end -- upgrades never replace an existing default
    if not self:Valid(snapshot,spec) then return nil,"BARS_INVALID" end
    state.default=clone(snapshot);state.defaultSource=source
    return true
end
function B:SaveIndependent(spec,buildID,snapshot)
    local state=self:Spec(spec)
    if not state then return nil,"SCHEMA" end
    if not self:Valid(snapshot,spec) or buildID==nil then return nil,"BARS_INVALID" end
    local key=tostring(buildID)
    if not state.profiles[key] then
        local count=0;for _ in pairs(state.profiles) do count=count+1 end
        if count>=self.profileLimit then return nil,"CAPACITY" end
    end
    state.profiles[key]=clone(snapshot)
    return true
end
function B:SaveLayout(spec,buildID,shared,snapshot)
    if not shared then return self:SaveIndependent(spec,buildID,snapshot) end
    local state=self:Spec(spec)
    if not state then return nil,"SCHEMA" end
    if not self:Valid(snapshot,spec) then return nil,"BARS_INVALID" end
    state.default=clone(snapshot)
    state.defaultSource="user-save"
    return true
end
function B:Get(spec,buildID,shared)
    local state=self:Spec(spec)
    if not state then return nil,"SCHEMA" end
    local snapshot
    if shared then snapshot=state.default else snapshot=state.profiles[tostring(buildID)] end
    if not snapshot then return nil,"BARS_MISSING" end
    if not self:Valid(snapshot,spec) then return nil,"BARS_INVALID" end
    return clone(snapshot)
end
local function secret(value) return issecretvalue and issecretvalue(value) end
function B:ReadSlot(slot)
    local kind,id,sub=GetActionInfo(slot)
    if secret(kind) or secret(id) or secret(sub) then return nil,"BARS_SECRET" end
    if not kind then return {} end
    -- PickupSpell mounts are reported as companion/spellID until the native
    -- loadout serializer normalizes them to summonmount/mountID.
    if kind=="companion" and sub=="MOUNT" then
        local mount=C_MountJournal.GetMountFromSpell(id)
        if not mount then return nil,"BARS_UNAVAILABLE" end
        kind,id,sub="summonmount",mount,nil
    end
    local entry={kind=kind,id=id,sub=sub}
    if kind=="macro" then
        -- GetActionInfo may describe the macro's spell/item, not its index.
        -- The native action button uses ignoreActionRemoval=true to copy an
        -- action to the cursor without removing the original slot.
        if InCombatLockdown() then return nil,"COMBAT" end
        if GetCursorInfo() then return nil,"BARS_CURSOR" end
        local ok,cursorKind,index=pcall(function()
            PickupAction(slot,true)
            return GetCursorInfo()
        end)
        ClearCursor()
        if not ok or secret(cursorKind) or secret(index) then return nil,"BARS_MACRO_READ" end
        -- Some slots report a macro but a successful copied pickup returns no
        -- cursor. Its identity is unknown: preserve that slot, never save it as
        -- empty or reinterpret GetActionInfo's spell/item ID as a macro index.
        if cursorKind==nil and index==nil then return {kind="unreadableMacro",id=slot} end
        if cursorKind~="macro" or type(index)~="number" or index<1 or index%1~=0 then return nil,"BARS_MACRO_READ" end
        local name=GetMacroInfo(index)
        if secret(name) then return nil,"BARS_SECRET" end
        if type(name)~="string" then return nil,"BARS_MACRO_READ" end
        entry.id=index;entry.sub=nil
    end
    return entry
end
function B:Capture(spec)
    if InCombatLockdown() then return nil,"COMBAT" end
    if A:GetSpec()~=spec then return nil,"APPLY_SPEC_CHANGED" end
    if GetCursorInfo() then return nil,"BARS_CURSOR" end
    if C_ActionBar then
        for _,name in ipairs({"HasVehicleActionBar","HasOverrideActionBar","IsPossessBarVisible"}) do
            if C_ActionBar[name] and C_ActionBar[name]() then return nil,"BARS_CONTEXT" end
        end
    end
    local slots={}
    for i=1,self.slotCount do
        local entry,why=self:ReadSlot(i)
        if not entry then return nil,why,i end
        slots[i]=entry
    end
    return {version=1,spec=spec,slots=slots}
end
local function baseSpell(id)
    if C_Spell and C_Spell.GetBaseSpell then
        local base=C_Spell.GetBaseSpell(id)
        if not secret(base) and type(base)=="number" and base>0 then return base end
    end
    return id
end
local function same(a,b)
    if a.kind~=b.kind then return false end
    if a.kind=="macro" then return a.id==b.id end
    -- Talent overrides can change the ID reported by GetActionInfo. Only
    -- normalize player spells; pet actions and macro identities stay exact.
    if a.kind=="spell" and (a.sub==nil or a.sub=="spell") and (b.sub==nil or b.sub=="spell") then
        return a.id==b.id or baseSpell(a.id)==baseSpell(b.id)
    end
    return a.id==b.id and a.sub==b.sub
end
function B:MacroIndex(entry)
    -- The saved absolute index is the reference, not the macro's name or text.
    -- Legacy metadata (including macroInvalid) must not block user edits.
    local index=entry.id
    if type(index)~="number" or index<1 or index%1~=0 then return nil end
    local name=GetMacroInfo(index)
    if secret(name) or type(name)~="string" then return nil end
    return index
end
function B:Pickup(entry)
    if entry.kind=="spell" then
        C_Spell.PickupSpell(entry.id)
        -- A saved talent override may no longer be directly pickable after
        -- switching builds. Resolve its native base ID, never a name match.
        if not GetCursorInfo() and (entry.sub==nil or entry.sub=="spell") then
            local base=baseSpell(entry.id)
            if base~=entry.id then C_Spell.PickupSpell(base) end
        end
    elseif entry.kind=="item" then C_Item.PickupItem(entry.id)
    elseif entry.kind=="macro" then
        local index=self:MacroIndex(entry)
        if not index then return nil,"BARS_MACRO" end
        PickupMacro(index)
    elseif entry.kind=="summonmount" then
        local _,spell=C_MountJournal.GetMountInfoByID(entry.id)
        if not spell then return nil,"BARS_UNAVAILABLE" end
        C_Spell.PickupSpell(spell)
    elseif entry.kind=="equipmentset" and C_EquipmentSet and C_EquipmentSet.PickupEquipmentSet then
        C_EquipmentSet.PickupEquipmentSet(entry.id)
    elseif entry.kind=="summonpet" and C_PetJournal and C_PetJournal.PickupPet then
        C_PetJournal.PickupPet(entry.id)
    elseif entry.kind=="flyout" then
        local bank=Enum.SpellBookSpellBank.Player
        local found
        for index=1,1024 do
            local info=C_SpellBook.GetSpellBookItemInfo(index,bank)
            if info and info.itemType==Enum.SpellBookItemType.Flyout and info.actionID==entry.id then found=index;break end
        end
        if not found then return nil,"BARS_UNAVAILABLE" end
        C_SpellBook.PickupSpellBookItem(found,bank)
    else return nil,"BARS_UNSUPPORTED" end
    if not GetCursorInfo() then return nil,"BARS_UNAVAILABLE" end
    return true
end
function B:FindSlot(entry,except)
    for slot=1,self.slotCount do
        if slot~=except then
            local actual=self:ReadSlot(slot)
            if actual and same(actual,entry) then return slot end
        end
    end
end
function B:Restore(snapshot)
    local spec=A:GetSpec()
    if InCombatLockdown() then return nil,"COMBAT" end
    if not self:Valid(snapshot,spec) then return nil,"BARS_INVALID" end
    if GetCursorInfo() then return nil,"BARS_CURSOR" end
    local before,why=self:Capture(spec)
    if not before then return nil,why end
    local changes,preserve,preservedSlots={},{},{}
    for slot=1,self.slotCount do
        if before.slots[slot].kind=="unreadableMacro" or snapshot.slots[slot].kind=="unreadableMacro" then
            preserve[slot]=true;preservedSlots[#preservedSlots+1]=slot
        elseif not same(before.slots[slot],snapshot.slots[slot]) then changes[#changes+1]=slot end
    end
    -- Preflight every pickup before removing/replacing any action. Unknown
    -- action types can remain in place but are never silently discarded.
    local moveFirst={}
    for _,slot in ipairs(changes) do
        local desired=snapshot.slots[slot]
        if desired.kind then
            local called,ok,reason=pcall(self.Pickup,self,desired)
            ClearCursor()
            if not called or not ok then
                if desired.kind=="spell" and self:FindSlot(desired) then moveFirst[slot]=true
                else return nil,reason or "BARS_UNAVAILABLE",slot end
            end
        end
        local old=before.slots[slot]
        if old.kind then
            local called,ok,reason=pcall(self.Pickup,self,old)
            ClearCursor()
            if (not called or not ok) and not (old.kind=="spell" and self:FindSlot(old)) then return nil,reason or "BARS_UNAVAILABLE",slot end
        end
    end
    -- Copy unavailable spells to their final slots before any replacement can
    -- discard their only existing action-bar instance.
    table.sort(changes,function(a,b)
        if moveFirst[a]~=moveFirst[b] then return moveFirst[a]==true end
        return a<b
    end)
    self.restoring=true
    local touched,seen={},{}
    local function remember(slot)
        if not seen[slot] then seen[slot]=true;touched[#touched+1]=slot end
    end
    local function put(slot,entry)
        local current=self:ReadSlot(slot)
        if current and current.kind=="unreadableMacro" then error("BARS_MACRO_READ:"..slot) end
        if current and same(current,entry) then return end
        remember(slot)
        if entry.kind then
            local source=self:FindSlot(entry,slot)
            if source then
                -- Copy, never move: the source may already be correct, and
                -- multiple destinations may need the same unavailable spell.
                PickupAction(source,true)
                if not GetCursorInfo() then error("BARS_UNAVAILABLE") end
                PlaceAction(slot)
            else
                local ok,reason=self:Pickup(entry)
                if not ok then error(reason) end
                PlaceAction(slot)
            end
        else PickupAction(slot) end
        ClearCursor()
        local actual=self:ReadSlot(slot)
        if not actual or not same(entry,actual) then error("BARS_VERIFY:"..slot..":"..tostring(actual and actual.kind)..":"..tostring(actual and actual.id)..":"..tostring(actual and actual.sub)) end
    end
    local verified
    local function verify(layout)
        local slots={}
        for slot=1,self.slotCount do
            if preserve[slot] then slots[slot]=clone(before.slots[slot])
            else
                local actual=self:ReadSlot(slot)
                if not actual or not same(layout.slots[slot],actual) then error("BARS_LAYOUT_VERIFY:"..slot) end
                slots[slot]=actual
            end
        end
        verified={version=1,spec=spec,slots=slots}
    end
    local ok,reason=pcall(function()
        for _,slot in ipairs(changes) do
            if InCombatLockdown() or A:GetSpec()~=spec then error("BARS_CONTEXT") end
            put(slot,snapshot.slots[slot])
        end
        verify(snapshot)
    end)
    local rolledBack=true
    if not ok then
        ClearCursor()
        if not InCombatLockdown() and A:GetSpec()==spec then
            for i=#touched,1,-1 do
                local slot=touched[i]
                local restored=pcall(put,slot,before.slots[slot])
                rolledBack=restored and rolledBack
            end
            local verified=pcall(verify,before)
            rolledBack=verified and rolledBack
        else rolledBack=false end
        self.recovery={before=before,requested=clone(snapshot),rolledBack=rolledBack}
    end
    self.restoring=nil
    if not ok then return nil,"BARS_RESTORE",{reason=tostring(reason),rolledBack=rolledBack} end
    self.verified=verified
    if #preservedSlots>0 then return true,nil,{preservedSlots=preservedSlots} end
    return true
end
-- Trust only the exact saved ID and name, including our pending rename.
function B:Working(spec)
    local state=self:Spec(spec)
    local binding=state and state.working
    if not binding then return end
    for _,id in ipairs(C_ClassTalents.GetConfigIDsBySpecID(spec) or {}) do
        if id==binding.id then
            local info=C_Traits.GetConfigInfo(id)
            if info and info.type==Enum.TraitConfigType.Combat then
                if binding.pendingName and info.name==binding.pendingName then binding.name=info.name;binding.pendingName=nil end
                if info.name==binding.name then return binding,info end
            end
            return
        end
    end
end
-- Full, cursor-assisted reads belong to Apply. Once it completes, ordinary
-- slot notifications only update this verified snapshot through passive APIs.
function B:Track(snapshot)
    local applied=A.Store.character.applied
    if not applied or not self:Valid(snapshot,applied.spec) then self.observed=nil;return end
    self.observed={spec=applied.spec,id=applied.id,shared=applied.shared,snapshot=clone(snapshot),macros={}}
    for slot,entry in ipairs(snapshot.slots) do
        if entry.kind=="macro" then self.observed.macros[slot]=entry.id end
    end
    if A.Apply and A.Apply.op then self:RememberMacroCounts() end
end
function B:PassiveSlot(slot,observed)
    local kind,id,sub=GetActionInfo(slot)
    if secret(kind) or secret(id) or secret(sub) then return nil,"BARS_SECRET" end
    if not kind then return {} end
    if kind=="macro" then
        local index=observed.macros[slot]
        local name=index and GetMacroInfo(index)
        if secret(name) then return nil,"BARS_SECRET" end
        if type(name)=="string" then
            -- A renamed/edited macro keeps its exact index. A different label
            -- without a known placement is unknown, never a name-based guess.
            local text=C_ActionBar and C_ActionBar.GetActionText and C_ActionBar.GetActionText(slot)
            if secret(text) then return nil,"BARS_SECRET" end
            if text==nil or text==name then return {kind="macro",id=index} end
        end
        return {kind="unreadableMacro",id=slot}
    end
    if kind=="companion" and sub=="MOUNT" then
        local mount=C_MountJournal.GetMountFromSpell(id)
        if not mount then return nil,"BARS_UNAVAILABLE" end
        kind,id,sub="summonmount",mount,nil
    end
    return {kind=kind,id=id,sub=sub}
end
function B:SaveActive(slot)
    if not A.Apply or A.Apply.op or self.restoring or InCombatLockdown() then return end
    local applied=A.Store.character.applied
    if not applied or applied.spec~=A:GetSpec() then return end
    if C_ActionBar then
        for _,name in ipairs({"HasVehicleActionBar","HasOverrideActionBar","IsPossessBarVisible"}) do
            if C_ActionBar[name] and C_ActionBar[name]() then return end
        end
    end
    local observed=self.observed
    if not observed or observed.spec~=applied.spec or observed.id~=applied.id or observed.shared~=applied.shared then
        self:Track(self:Get(applied.spec,applied.id,applied.shared))
        observed=self.observed
        if not observed then return end
    end
    if secret(slot) then return end
    if slot~=nil and slot~=0 and (type(slot)~="number" or slot<1 or slot>self.slotCount or slot%1~=0) then return end
    local first,last=1,self.slotCount
    if slot and slot~=0 then first,last=slot,slot end
    local changes={}
    for i=first,last do
        local entry=self:PassiveSlot(i,observed)
        if not entry then return end -- atomic: don't save a partial scan
        if not same(entry,observed.snapshot.slots[i]) then changes[i]=entry end
    end
    if not next(changes) then return end
    if A.Apply:CurrentBuildID()~=applied.id then return end
    local snapshot=clone(observed.snapshot)
    for i,entry in pairs(changes) do snapshot.slots[i]=entry end
    if self:SaveLayout(applied.spec,applied.id,applied.shared,snapshot) then
        observed.snapshot=snapshot
        for i,entry in pairs(changes) do
            if entry.kind~="macro" and entry.kind~="unreadableMacro" then observed.macros[i]=nil end
        end
    end
end
function B:CursorChanged()
    if A.Apply and A.Apply.op then self.cursorMacro=nil;self.cursorDrop=nil;return end
    -- Read the player's existing cursor; never put anything on it. Retain the
    -- outgoing macro for PlaceAction's post-hook, even when the displaced action
    -- has already replaced it (CURSOR_CHANGED is a synchronous native event).
    local outgoing=self.cursorMacro
    self:RememberCursor()
    -- Observe GetCursorInfo's real index, not a virtual cursor ID or a macro
    -- label. Repainting the same held macro is not a placement transition.
    if outgoing~=self.cursorMacro then self.cursorDrop=outgoing end
end
function B:RememberCursor()
    local kind,index=GetCursorInfo()
    self.cursorMacro=not secret(kind) and not secret(index) and kind=="macro" and index or nil
end
function B:Placed(slot)
    local index=self.cursorDrop;self.cursorDrop=nil
    self:RememberCursor()
    if not A.Apply or A.Apply.op or self.restoring then return end
    local applied=A.Store.character.applied
    if not applied or applied.spec~=A:GetSpec() or A.Apply:CurrentBuildID()~=applied.id then return end
    if not self.observed or self.observed.spec~=applied.spec or self.observed.id~=applied.id or self.observed.shared~=applied.shared then
        self:Track(self:Get(applied.spec,applied.id,applied.shared))
    end
    if not self.observed then return end
    if secret(slot) or type(slot)~="number" or slot<1 or slot>self.slotCount or slot%1~=0 then return end
    if type(index)=="number" and index>0 and index%1==0 then
        local kind=GetActionInfo(slot)
        local name=GetMacroInfo(index)
        if not secret(kind) and not secret(name) and kind=="macro" and type(name)=="string" then
            self.observed.macros[slot]=index
        end
    end
    self:SaveActive(slot)
end
function B:MacroDeleted(index)
    local counts=self.macroCounts
    self:RememberMacroCounts()
    if not counts or not self.macroCounts or not self.observed or (A.Apply and A.Apply.op) or self.restoring or InCombatLockdown() then return end
    local applied=A.Store.character.applied
    if not applied or applied.spec~=A:GetSpec() or A.Apply:CurrentBuildID()~=applied.id then return end
    if secret(index) or type(index)~="number" or index<1 or index%1~=0 then return end
    -- Native deletion compacts indices within the account/character range.
    -- Only the active layout follows that edit; saved layouts keep their IDs.
    local account=MAX_ACCOUNT_MACROS or 120
    local scope=index>account and 2 or 1
    -- A rejected/protected native deletion must not shift our cached IDs.
    if self.macroCounts[scope]~=counts[scope]-1 then return end
    for slot,id in pairs(self.observed.macros) do
        if id==index then self.observed.macros[slot]=nil
        elseif id>index and (id>account)==(index>account) then self.observed.macros[slot]=id-1 end
    end
    self:SaveActive()
end
function B:RememberMacroCounts()
    if not GetNumMacros then return end
    local account,character=GetNumMacros()
    if not secret(account) and not secret(character) and type(account)=="number" and type(character)=="number" then
        self.macroCounts={account,character}
    end
end
function B:Init()
    if self.events then return end
    local frame=CreateFrame("Frame");self.events=frame
    for _,event in ipairs({"PLAYER_ENTERING_WORLD","ACTIVE_PLAYER_SPECIALIZATION_CHANGED","PLAYER_REGEN_ENABLED","ACTIONBAR_SLOT_CHANGED","PLAYER_LOGOUT","CURSOR_CHANGED","UPDATE_MACROS"}) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent",function(_,event,...)
        if event=="CURSOR_CHANGED" then self:CursorChanged(...)
        elseif event=="ACTIONBAR_SLOT_CHANGED" then self:SaveActive(...)
        elseif event=="ACTIVE_PLAYER_SPECIALIZATION_CHANGED" or event=="PLAYER_ENTERING_WORLD" then
            self.observed=nil;self.cursorDrop=nil;self.cursorMacro=nil
        else self:SaveActive() end
    end)
    if hooksecurefunc then
        hooksecurefunc("PlaceAction",function(slot)B:Placed(slot)end)
        for _,name in ipairs({"ClearCursor","PickupAction","PickupMacro"}) do
            hooksecurefunc(name,function()B.cursorDrop=nil;B:RememberCursor()end)
        end
        hooksecurefunc("DeleteMacro",function(index)B:MacroDeleted(index)end)
        for _,name in ipairs({"CreateMacro","EditMacro"}) do
            if type(_G[name])=="function" then hooksecurefunc(name,function()B:RememberMacroCounts()end) end
        end
    end
    self:RememberMacroCounts()
    self:CursorChanged()
end
