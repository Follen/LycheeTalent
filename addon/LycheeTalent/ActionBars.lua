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
        if not ok or secret(cursorKind) or secret(index) then return nil,"BARS_MACRO" end
        if cursorKind~="macro" or type(index)~="number" or index<1 or index%1~=0 then return nil,"BARS_MACRO" end
        local name,_,body=GetMacroInfo(index)
        if secret(name) or secret(body) then return nil,"BARS_SECRET" end
        if type(name)~="string" or type(body)~="string" then return nil,"BARS_MACRO" end
        entry.id=index;entry.name=name;entry.body=body
        entry.character=index>(MAX_ACCOUNT_MACROS or 120)
    end
    return entry
end
function B:Capture(spec)
    if InCombatLockdown() then return nil,"COMBAT" end
    if A:GetSpec()~=spec then return nil,"APPLY_SPEC_CHANGED" end
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
local function sameMacroBody(a,b)
    if type(a)~="string" or type(b)~="string" then return false end
    -- Saved layouts can retain a final newline omitted by GetMacroInfo later.
    -- Keep commands, internal whitespace and exact macro-slot identity intact.
    return a==b or a:gsub("[\r\n]+$","")==b:gsub("[\r\n]+$","")
end
local function same(a,b)
    if a.kind~=b.kind then return false end
    if a.kind=="macro" then return not a.macroInvalid and not b.macroInvalid and a.id==b.id and a.name==b.name and sameMacroBody(a.body,b.body) and a.character==b.character end
    -- Talent overrides can change the ID reported by GetActionInfo. Only
    -- normalize player spells; pet actions and macro identities stay exact.
    if a.kind=="spell" and (a.sub==nil or a.sub=="spell") and (b.sub==nil or b.sub=="spell") then
        return a.id==b.id or baseSpell(a.id)==baseSpell(b.id)
    end
    return a.id==b.id and a.sub==b.sub
end
function B:MacroIndex(entry)
    -- Macro indices are the identity available to the action bar. Never
    -- substitute another index merely because its name/body looks equivalent.
    local index=entry.id
    if entry.macroInvalid then return nil end
    if type(index)~="number" or index<1 or index%1~=0 then return nil end
    if (index>(MAX_ACCOUNT_MACROS or 120))~=entry.character then return nil end
    local name,_,body=GetMacroInfo(index)
    if secret(name) or secret(body) then return nil end
    if name==entry.name and sameMacroBody(body,entry.body) then return index end
    return nil
end
-- Observe each synchronous UPDATE_MACROS separately: an edit may update saved
-- references, but deletion followed by creation must not adopt a replacement.
function B:UpdateMacros()
    if not GetNumMacros or not GetMacroInfo then return end
    local account,character=GetNumMacros()
    if secret(account) or secret(character) or type(account)~="number" or type(character)~="number" then return end
    local current={}
    local limit=MAX_ACCOUNT_MACROS or 120
    for _,range in ipairs({{1,account},{limit+1,limit+character}}) do
        for index=range[1],range[2] do
            local name,_,body=GetMacroInfo(index)
            if secret(name) or secret(body) or type(name)~="string" or type(body)~="string" then return end
            current[index]={kind="macro",id=index,name=name,body=body,character=index>limit}
        end
    end
    local previous=self.macroCatalog
    local stableCounts=account==self.macroAccountCount and character==self.macroCharacterCount
    self.macroCatalog=current
    self.macroAccountCount,self.macroCharacterCount=account,character
    if not previous or A.Store.readonly then return end
    local bars=A.Store.character and A.Store.character.actionBars
    if type(bars)~="table" or bars.version~=1 or type(bars.specs)~="table" then return end
    local function update(snapshot,spec)
        if not self:Valid(snapshot,spec) then return end
        for _,entry in ipairs(snapshot.slots) do
            local old=entry.kind=="macro" and previous[entry.id]
            if old and same(entry,old) then
                local new=current[entry.id]
                if new and same(old,new) then
                    entry.body=new.body
                elseif new and new.name==old.name and stableCounts then
                    -- Only an observed content edit at the original index.
                    entry.body=new.body
                else
                    entry.macroInvalid=true
                end
            end
        end
    end
    for spec,state in pairs(bars.specs) do
        if type(state)=="table" then
            update(state.default,spec)
            if type(state.profiles)=="table" then
                for _,snapshot in pairs(state.profiles) do update(snapshot,spec) end
            end
        end
    end
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
    local changes={}
    for slot=1,self.slotCount do
        if not same(before.slots[slot],snapshot.slots[slot]) then changes[#changes+1]=slot end
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
    local function verify(layout)
        for slot=1,self.slotCount do
            local actual=self:ReadSlot(slot)
            if not actual or not same(layout.slots[slot],actual) then error("BARS_LAYOUT_VERIFY:"..slot) end
        end
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
function B:SaveActive()
    if not A.Apply or A.Apply.op or self.restoring then return end
    local applied=A.Store.character.applied
    if not applied or applied.shared or applied.spec~=A:GetSpec() then return end
    if A.Apply:CurrentBuildID()~=applied.id then return end
    local snapshot=self:Capture(applied.spec)
    if snapshot then self:SaveIndependent(applied.spec,applied.id,snapshot) end
end
function B:InitializeSpec()
    local spec=A:GetSpec()
    if not spec or InCombatLockdown() then return end
    local state=self:Spec(spec)
    if state and not state.default then
        local snapshot=self:Capture(spec)
        if snapshot then self:SeedDefault(spec,snapshot,"first-use") end
    end
end
function B:Init()
    if self.events then return end
    local frame=CreateFrame("Frame");self.events=frame
    for _,event in ipairs({"PLAYER_ENTERING_WORLD","ACTIVE_PLAYER_SPECIALIZATION_CHANGED","PLAYER_REGEN_ENABLED","ACTIONBAR_SLOT_CHANGED","PLAYER_LOGOUT","UPDATE_MACROS"}) do frame:RegisterEvent(event) end
    frame:SetScript("OnEvent",function(_,event)
        if event=="UPDATE_MACROS" then self:UpdateMacros();return end
        if event=="PLAYER_LOGOUT" then self:SaveActive();return end
        if event=="ACTIONBAR_SLOT_CHANGED" then
            if self.restoring or (A.Apply and A.Apply.op) or self.saveTimer then return end
            self.saveTimer=C_Timer.NewTimer(0,function()self.saveTimer=nil;self:SaveActive()end)
        else self:InitializeSpec() end
    end)
    self:UpdateMacros()
    self:InitializeSpec()
end
