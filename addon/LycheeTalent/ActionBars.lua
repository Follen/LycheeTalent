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
        -- Without a subtype, GetActionInfo already returns the macro index.
        -- Only spell/item presentation needs a cursor read to recover identity.
        if not sub then
            if not self:MacroIndex(entry) then return nil,"BARS_MACRO_READ" end
            return entry
        end
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
        -- Random favorite is an action-bar sentinel, not a mount journal ID.
        if entry.id==0x0FFFFFFF then C_MountJournal.Pickup(0)
        else
            local _,spell=C_MountJournal.GetMountInfoByID(entry.id)
            if not spell then return nil,"BARS_UNAVAILABLE" end
            C_Spell.PickupSpell(spell)
        end
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
local function findSlot(slots,entry,except)
    for slot=1,B.slotCount do
        local actual=slots[slot]
        if slot~=except and actual and same(actual,entry) then return slot end
    end
end
function B:Restore(snapshot)
    local spec=A:GetSpec()
    if InCombatLockdown() then return nil,"COMBAT" end
    if not self:Valid(snapshot,spec) then return nil,"BARS_INVALID" end
    if GetCursorInfo() then return nil,"BARS_CURSOR" end
    local before,why=self:Capture(spec)
    if not before then return nil,why end
    local current=clone(before.slots)
    local target=clone(snapshot)
    local changes,preserve,preservedSlots={},{},{}
    for slot=1,self.slotCount do
        -- Old partial snapshots have no identity to restore. Adopt the current
        -- action once it is readable so the placeholder does not survive forever.
        if target.slots[slot].kind=="unreadableMacro" then target.slots[slot]=clone(before.slots[slot]) end
        if before.slots[slot].kind=="unreadableMacro" then
            preserve[slot]=true;preservedSlots[#preservedSlots+1]=slot
        elseif not same(before.slots[slot],target.slots[slot]) then changes[#changes+1]=slot end
    end
    -- Preflight every pickup before removing/replacing any action. Unknown
    -- action types can remain in place but are never silently discarded.
    local moveFirst={}
    for _,slot in ipairs(changes) do
        local desired=target.slots[slot]
        if desired.kind then
            local called,ok,reason=pcall(self.Pickup,self,desired)
            ClearCursor()
            if not called or not ok then
                if desired.kind=="spell" and findSlot(current,desired) then moveFirst[slot]=true
                else return nil,reason or "BARS_UNAVAILABLE",slot end
            end
        end
        local old=before.slots[slot]
        if old.kind then
            local called,ok,reason=pcall(self.Pickup,self,old)
            ClearCursor()
            if (not called or not ok) and not (old.kind=="spell" and findSlot(current,old)) then return nil,reason or "BARS_UNAVAILABLE",slot end
        end
    end
    -- Copy unavailable spells to their final slots before any replacement can
    -- discard their only existing action-bar instance.
    table.sort(changes,function(a,b)
        if moveFirst[a]~=moveFirst[b] then return moveFirst[a]==true end
        return a<b
    end)
    local touched,seen={},{}
    local function remember(slot)
        if not seen[slot] then seen[slot]=true;touched[#touched+1]=slot end
    end
    local function put(slot,entry)
        if current[slot] and same(current[slot],entry) then return end
        remember(slot)
        current[slot]=nil -- a failed write must still be restored during rollback
        if entry.kind then
            local source=entry.kind=="spell" and findSlot(current,entry,slot)
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
        current[slot]=clone(entry)
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
            put(slot,target.slots[slot])
        end
        verify(target)
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
