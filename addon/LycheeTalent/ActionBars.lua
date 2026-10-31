local _, A = ...
local B = {slotCount=180,profileLimit=1000}
A.ActionBars=B
-- Each specialization has one default and independent profiles per build.
function B:Spec(spec)
    local char=A.Store.character
    if not char or type(spec)~="number" or spec<=0 or spec%1~=0 then return nil end
    char.actionBars=char.actionBars or {version=1,specs={}}
    if type(char.actionBars)~="table" or char.actionBars.version~=1 or type(char.actionBars.specs)~="table" then return nil end
    local specs=char.actionBars.specs
    if not specs[spec] then specs[spec]={profiles={}} end
    if type(specs[spec])~="table" or type(specs[spec].profiles)~="table" then return nil end
    return specs[spec]
end
function B:IsShared(spec,buildID)
    local state=self:Spec(spec)
    if not state then return true end
    state.modes=state.modes or {}
    local key=tostring(buildID)
    return state.modes[key]~=false
end
function B:SetShared(spec,buildID,shared)
    local state=self:Spec(spec);if not state then return nil,"SCHEMA" end
    state.modes=state.modes or {};state.modes[tostring(buildID)]=shared==true
    return true
end
local function clone(value)
    local out={}
    for k,v in pairs(value) do out[k]=type(v)=="table" and clone(v) or v end
    return out
end
function B:Valid(snapshot,spec)
    if type(snapshot)~="table" or snapshot.version~=2 or snapshot.spec~=spec
        or type(snapshot.slots)~="table" or #snapshot.slots~=self.slotCount then return false end
    for i=1,self.slotCount do
        local entry=snapshot.slots[i]
        if type(entry)~="table" then return false end
        if entry.kind=="unreadableMacro" and entry.id~=i then return false end
        if entry.kind~=nil and (type(entry.kind)~="string" or
            (type(entry.id)~="number" and type(entry.id)~="string")) then return false end
        if entry.kind=="macro" then
            local macro=snapshot.macros and snapshot.macros[entry.id]
            if type(macro)~="table" or type(macro.name)~="string" or type(macro.body)~="string"
                or type(macro.nativeID)~="string" or macro.nativeID=="" then return false end
        end
    end
    return true
end
function B:SeedDefault(spec,snapshot,source)
    local state=self:Spec(spec)
    if not state then return nil,"SCHEMA" end
    if state.default then return true end -- never replace a captured default
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
-- A verified physical snapshot consumes both slot edits and macro revisions.
-- Ordinary macro-only saves must not clear a queued real slot edit.
function B:ConfirmSlots(spec)
    if not self.slotDirtySpec or self.slotDirtySpec==spec then self.slotDirty=nil;self.slotDirtySpec=nil end
    self.macroRevision=A.Macros.revision;self.macroDirty=nil
end
function B:SaveLayout(spec,buildID,shared,snapshot)
    if not shared then
        local ok,why=self:SaveIndependent(spec,buildID,snapshot)
        if ok and snapshot==self.verified then self:ConfirmSlots(spec) end
        return ok,why
    end
    local state=self:Spec(spec)
    if not state then return nil,"SCHEMA" end
    if not self:Valid(snapshot,spec) then return nil,"BARS_INVALID" end
    state.default=clone(snapshot)
    state.defaultSource="user-save"
    if snapshot==self.verified then self:ConfirmSlots(spec) end
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
function B:ReadSlot(slot,passive,native)
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
        local text=C_ActionBar and C_ActionBar.GetActionText and C_ActionBar.GetActionText(slot)
        local index=not secret(text) and text and A.Macros:Named(native or A.Macros:Scan(),text)
        if index then entry.id=index;entry.sub=nil;return entry end
        if passive then return {kind="unreadableMacro",id=slot} end
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
function B:CapturePhysical(spec,passive)
    if InCombatLockdown() then return nil,"COMBAT" end
    if A:GetSpec()~=spec then return nil,"APPLY_SPEC_CHANGED" end
    if not passive and GetCursorInfo() then return nil,"BARS_CURSOR" end
    if C_ActionBar then
        for _,name in ipairs({"HasVehicleActionBar","HasOverrideActionBar","IsPossessBarVisible"}) do
            if C_ActionBar[name] and C_ActionBar[name]() then return nil,"BARS_CONTEXT" end
        end
    end
    local slots={};local native=A.Macros:Scan()
    for i=1,self.slotCount do
        local entry,why=self:ReadSlot(i,passive,native)
        if not entry then return nil,why,i end
        slots[i]=entry
    end
    return {version=1,spec=spec,slots=slots}
end
function B:Capture(spec,passive,previous)
    self.reading=true
    local ok,snapshot,why,slot=pcall(self.CapturePhysical,self,spec,passive)
    self.reading=nil
    if not ok then return nil,"BARS_MACRO_READ" end
    if not snapshot then return nil,why,slot end
    local packed,reason=A.Macros:Pack(snapshot);if not packed then return nil,reason end
    if not previous then
        local state=self:Spec(spec);local applied=state and state.applied
        previous=applied and self:Get(spec,applied.id,applied.shared)
    end
    return self:PreservePending(self:PreserveDeferred(packed,previous),previous)
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
function B:PreserveDeferred(snapshot,previous)
    for slot,entry in pairs(previous and previous.deferredSpells or {}) do
        local actual,old=snapshot.slots[slot],previous.slots[slot]
        local unchanged=same(actual,old)
        if actual.kind=="macro" and old.kind=="macro" then
            unchanged=snapshot.macros[actual.id].nativeID==previous.macros[old.id].nativeID
        end
        -- Keep unavailable talent spells until the user changes this slot.
        -- Passive reads and switching away must not turn them into deletions.
        if unchanged then
            snapshot.deferredSpells=snapshot.deferredSpells or {}
            snapshot.deferredSpells[slot]=clone(entry)
        end
    end
    return snapshot
end
function B:PreservePending(snapshot,previous)
    if not previous then return snapshot end
    local function unchanged(slot,observed,macro)
        local actual=snapshot.slots[slot]
        if actual.kind=="macro" and observed.kind=="macro" then
            return macro and snapshot.macros[actual.id].nativeID==macro.nativeID
        end
        return same(actual,observed)
    end
    for slot,pending in pairs(previous.pendingMacros or {}) do
        if unchanged(slot,pending.observed,pending.observedMacro) then
            snapshot.pendingMacros=snapshot.pendingMacros or {}
            snapshot.pendingMacros[slot]=clone(pending)
        end
    end
    -- Native deletion clears its action buttons. Keep the missing reference
    -- instead of letting a passive observation erase its only backup.
    local native
    for slot,entry in ipairs(previous.slots) do
        if entry.kind=="macro" and not snapshot.slots[slot].kind then
            native=native or A.Macros:Current()
            local macro=previous.macros[entry.id]
            if not A.Macros:Resolve(macro,native) then
                snapshot.pendingMacros=snapshot.pendingMacros or {}
                snapshot.pendingMacros[slot]={macro=clone(macro),observed={}}
            end
        end
    end
    return snapshot
end
local function unlearned(entry)
    return entry.kind=="spell" and (entry.sub==nil or entry.sub=="spell")
        and C_Spell.GetSpellInfo(entry.id)
        and not C_SpellBook.IsSpellKnown(entry.id) and not C_SpellBook.IsSpellKnown(baseSpell(entry.id))
end
function B:MacroIndex(entry)
    -- Only physical execution entries reach this helper.
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
function B:RestorePhysical(snapshot,validate)
    local spec=A:GetSpec()
    if InCombatLockdown() then return nil,"COMBAT" end
    if GetCursorInfo() then return nil,"BARS_CURSOR" end
    local before,why=self:CapturePhysical(spec)
    if not before then return nil,why end
    local current=clone(before.slots)
    local target=clone(snapshot)
    local changes,preserve,preservedSlots={},{},{}
    for slot=1,self.slotCount do
        -- Unresolved slots have no identity to restore. Adopt the current
        -- action once it is readable so the placeholder does not survive forever.
        if target.slots[slot].kind=="unreadableMacro" then target.slots[slot]=clone(before.slots[slot]) end
        if before.slots[slot].kind=="unreadableMacro" then
            preserve[slot]=true;preservedSlots[#preservedSlots+1]=slot
        elseif not same(before.slots[slot],target.slots[slot]) then changes[#changes+1]=slot end
    end
    -- Preflight every pickup before removing/replacing any action. Unknown
    -- action types can remain in place but are never silently discarded.
    local moveFirst,deferredSpells={},{}
    for _,slot in ipairs(changes) do
        local desired=target.slots[slot]
        if desired.kind then
            local called,ok,reason=pcall(self.Pickup,self,desired)
            ClearCursor()
            if not called or not ok then
                if desired.kind=="spell" and findSlot(current,desired) then moveFirst[slot]=true
                elseif called and reason=="BARS_UNAVAILABLE" and unlearned(desired) then
                    deferredSpells[slot]=clone(desired)
                    target.slots[slot]=clone(before.slots[slot])
                else return nil,reason or "BARS_UNAVAILABLE",{slot=slot,kind=desired.kind,id=desired.id,phase="pickup"} end
            end
        end
        local old=before.slots[slot]
        if old.kind and not deferredSpells[slot] then
            local called,ok,reason=pcall(self.Pickup,self,old)
            ClearCursor()
            if (not called or not ok) and not (old.kind=="spell" and findSlot(current,old)) then
                return nil,reason or "BARS_UNAVAILABLE",{slot=slot,kind=old.kind,id=old.id,phase="backup"}
            end
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
    local failureCode,failureDetail
    local ok,reason=pcall(function()
        for _,slot in ipairs(changes) do
            if InCombatLockdown() or A:GetSpec()~=spec then error("BARS_CONTEXT") end
            put(slot,target.slots[slot])
        end
        verify(target)
        if validate then
            local valid
            valid,failureCode,failureDetail=validate(verified)
            if not valid then error(failureCode) end
        end
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
    if not ok then
        local detail=failureDetail or {reason=tostring(reason)}
        detail.rolledBack=rolledBack
        return nil,failureCode or "BARS_RESTORE",detail
    end
    self.verified=verified
    self.verified.deferredSpells=next(deferredSpells) and deferredSpells or nil
    if #preservedSlots>0 then return true,nil,{preservedSlots=preservedSlots} end
    return true
end
-- Missing native references preserve their physical slot and original backup.
function B:Restore(snapshot)
    local spec=A:GetSpec()
    if not self:Valid(snapshot,spec) then return nil,"BARS_INVALID" end
    if InCombatLockdown() then return nil,"COMBAT" end
    if GetCursorInfo() then return nil,"BARS_CURSOR" end
    local target=clone(snapshot)
    for slot,entry in pairs(target.deferredSpells or {}) do target.slots[slot]=clone(entry) end
    target.deferredSpells=nil
    target.macros=target.macros or {}
    for slot,pending in pairs(target.pendingMacros or {}) do
        local ref="pending:"..slot
        target.macros[ref]=clone(pending.macro);target.slots[slot]={kind="macro",id=ref}
    end
    target.pendingMacros=nil
    local before,why=self:Capture(spec);if not before then return nil,why end
    local physical,missing=A.Macros:Physical(target)
    for slot,entry in ipairs(before.slots) do
        if entry.kind=="unreadableMacro" and target.slots[slot].kind=="macro" then
            missing[slot]=clone(target.macros[target.slots[slot].id])
            physical.slots[slot]=clone(entry)
        end
    end
    self.writing=true;self.verified=nil
    local verified
    local ok,result,reason,detail=pcall(function()
        local restored,err,info=self:RestorePhysical(physical,function(actual)
            local why
            verified,why=A.Macros:Pack(clone(actual))
            if not verified then return nil,why,{phase="macro-reference"} end
            for slot,entry in ipairs(target.slots) do
                if entry.kind=="macro" and not missing[slot] then
                    local found=verified.slots[slot]
                    if found.kind~="macro" or verified.macros[found.id].nativeID~=target.macros[entry.id].nativeID then
                        return nil,"BARS_MACRO",{phase="macro-reference",slot=slot}
                    end
                end
            end
            return true
        end)
        if not restored then
            info=info or {};if info.rolledBack==nil then info.rolledBack=true end
            return nil,err,info
        end
        verified.deferredSpells=self.verified.deferredSpells
        local missingSlots={}
        for slot,macro in pairs(missing) do
            verified.pendingMacros=verified.pendingMacros or {}
            local actual=verified.slots[slot]
            verified.pendingMacros[slot]={macro=clone(macro),observed=clone(actual),
                observedMacro=actual.kind=="macro" and clone(verified.macros[actual.id]) or nil}
            missingSlots[#missingSlots+1]=slot
        end
        table.sort(missingSlots)
        self.verified=verified
        info=info or {};info.missingMacros=#missingSlots>0 and missingSlots or nil
        return true,nil,info
    end)
    if not ok or not result then
        detail=type(detail)=="table" and detail or {rolledBack=false,reason=tostring(result)}
        self.verified=nil
        self.recovery={before=before,requested=target,rolledBack=detail.rolledBack,detail=detail}
        if not detail.rolledBack then self.pendingSpec=spec;self.resumeFailed=true end
        reason=ok and reason or "BARS_RESTORE"
    elseif self.pendingSpec==spec and self.resumeFailed then
        self.pendingSpec=nil;self.resumeFailed=nil
    end
    self.writing=nil
    if not ok or not result then return nil,reason,detail end
    return true,nil,detail
end
function B:Owner()
    local spec=A:GetSpec();local state=self:Spec(spec)
    if self.observedSpec and self.observedSpec~=spec then return end
    local applied=state and state.applied
    if not state or self.pendingSpec or state.pendingBars or not applied or not A.Apply:CurrentBuildID() then return end
    return spec,applied
end
function B:ObserveMacros()
    if not self:Spec(A:GetSpec()) then return end
    local _,changed=A.Macros:Current()
    -- Another capture may have synchronized the registry before this notice.
    -- Only a successful layout save consumes that content revision.
    if changed==false and self.macroRevision==A.Macros.revision then self.macroDirty=nil;return end
    self.macroDirty=true
    if self.writing or self.reading or A.Apply.op or InCombatLockdown() then return end
    local spec,applied=self:Owner()
    if applied then
        local snapshot=self:Get(spec,applied.id,applied.shared)
        if snapshot then
            A.Macros:Refresh(snapshot)
            if self:SaveLayout(spec,applied.id,applied.shared,snapshot) then self.macroRevision=A.Macros.revision;self.macroDirty=nil end
        end
    end
end
function B:ObserveSlots()
    if self.reading or self.writing or A.Apply.op or InCombatLockdown() then return end
    local spec,applied=self:Owner();if not applied then return end
    local previous=self:Get(spec,applied.id,applied.shared)
    local snapshot=self:Capture(spec,true,previous);if not snapshot then return end
    -- A passive read cannot resolve duplicate display names. Retain their
    -- last known content until the next explicit, cursor-assisted capture.
    if previous then
        for slot,entry in ipairs(snapshot.slots) do
            local old=previous.slots[slot]
            if entry.kind=="unreadableMacro" and old.kind=="macro" then
                local ref=old.id
                snapshot.slots[slot]={kind="macro",id=ref}
                snapshot.macros[ref]=snapshot.macros[ref] or clone(previous.macros[old.id])
            end
        end
    end
    if not self:SaveLayout(spec,applied.id,applied.shared,snapshot) then return end
    self:ConfirmSlots(spec)
    local pending=next(snapshot.pendingMacros or {})~=nil
    for _,entry in ipairs(snapshot.slots) do if entry.kind=="unreadableMacro" then pending=true;break end end
    if pending~=(applied.partial==true) then
        applied.partial=pending
        if A.UI and A.UI.UpdateBarsPending then A.UI:UpdateBarsPending(applied.id,pending) end
    end
end
function B:ResumeSpec()
    if not self.pendingSpec or self.resumeFailed or A.Apply.op or InCombatLockdown() or GetCursorInfo() then return end
    local spec=A:GetSpec();local state=self:Spec(spec);local applied=state and state.applied
    if not applied or not A.Apply:CurrentBuildID(true) then return end
    if state.pendingBars then self.resumeFailed=true;return end
    local snapshot=self:Get(spec,applied.id,applied.shared);if not snapshot then return end
    local ok,why,detail=self:Restore(snapshot)
    if not ok then
        self.resumeFailed=true
        if A.Apply.RememberFailure then A.Apply:RememberFailure({time=time(),spec=spec,buildID=applied.id,
            reason="BARS_PENDING",partial=true,actionBarsReason=why,stage="resume-bars",slot=detail and detail.slot}) end
        return
    end
    local saved,saveWhy=self:SaveLayout(spec,applied.id,applied.shared,self.verified)
    if not saved then
        self.resumeFailed=true
        if A.Apply.RememberFailure then A.Apply:RememberFailure({time=time(),spec=spec,buildID=applied.id,
            reason="BARS_PENDING",partial=true,actionBarsReason=saveWhy,stage="resume-save"}) end
        return
    end
    self.pendingSpec=nil
    applied.partial=detail and (detail.missingMacros~=nil or detail.preservedSlots~=nil) or false
    if applied.partial and A.Apply.RememberFailure then A.Apply:RememberFailure({time=time(),spec=spec,buildID=applied.id,
        reason="BARS_PENDING",partial=true,actionBarsReason="BARS_PARTIAL",stage="resume-bars",
        slots=table.concat(detail.missingMacros or detail.preservedSlots,",")}) end
end
function B:QueueObservation()
    if self.queued then return end
    self.queued=C_Timer.NewTimer(0,function()
        self.queued=nil
        if self.reading or self.writing or A.Apply.op or InCombatLockdown() then return end
        if self.pendingSpec then self:ResumeSpec() end
        if self.pendingSpec then return end
        if self.slotDirty then self:ObserveSlots() end
        if self.macroDirty or self.macroRevision~=A.Macros.revision then self:ObserveMacros() end
    end)
end
-- TRAIT_CONFIG_UPDATED carries a config ID. Unrelated saved loadouts do
-- not change our active talents, owned layout, or a pending recovery target.
function B:RelevantConfig(config)
    if type(config)~="number" or config<=0 then return true end
    local active=C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    if not active then return true end -- data not ready: do not discard a notice
    if config==active then return true end
    local spec=A:GetSpec();local state=self:Spec(spec)
    if state and C_ClassTalents.GetLastSelectedSavedConfigID and config==C_ClassTalents.GetLastSelectedSavedConfigID(spec) then return true end
    if state and state.working and config==state.working.id then return true end
    if state and state.applied and (state.pendingBars or self.pendingSpec==spec) and config==state.applied.config then return true end
    local op=A.Apply and A.Apply.op
    if op and (config==op.target or config==op.loading) then return true end
    local recovery=A.Store.character and A.Store.character.recovery
    if recovery and recovery.spec==spec and recovery.status~="complete" and config==recovery.targetConfig then return true end
    return false
end
local currentEvents={PLAYER_ENTERING_WORLD=true,PLAYER_LEAVING_WORLD=true,ACTIVE_PLAYER_SPECIALIZATION_CHANGED=true,
    PLAYER_TALENT_UPDATE=true,SELECTED_LOADOUT_CHANGED=true,ACTIVE_COMBAT_CONFIG_CHANGED=true,
    TRAIT_CONFIG_UPDATED=true,TRAIT_CONFIG_LIST_UPDATED=true,TRAIT_CONFIG_CREATED=true,CONFIG_COMMIT_FAILED=true,
    PLAYER_REGEN_ENABLED=true}
function B:Init()
    if self.events then return end
    local current=self:Spec(A:GetSpec())
    if current then A.Macros:Initialize();self.macroRevision=A.Macros.revision end
    if current and current.pendingBars then self.pendingSpec=A:GetSpec();self.resumeFailed=true end
    local events=CreateFrame("Frame");self.events=events
    for _,event in ipairs({"UPDATE_MACROS","ACTIONBAR_SLOT_CHANGED","PLAYER_LOGOUT","PLAYER_ENTERING_WORLD",
        "ACTIVE_PLAYER_SPECIALIZATION_CHANGED","PLAYER_REGEN_ENABLED","CURSOR_CHANGED","PLAYER_TALENT_UPDATE",
        "SELECTED_LOADOUT_CHANGED","ACTIVE_COMBAT_CONFIG_CHANGED","TRAIT_CONFIG_UPDATED","TRAIT_CONFIG_LIST_UPDATED",
        "TRAIT_CONFIG_CREATED","CONFIG_COMMIT_FAILED","PLAYER_LEAVING_WORLD"}) do events:RegisterEvent(event) end
    events:SetScript("OnEvent",function(_,event,value)
        if event=="TRAIT_CONFIG_UPDATED" and not self:RelevantConfig(value) then return end
        if event=="ACTIONBAR_SLOT_CHANGED" then self.slotDirty=true;self.slotDirtySpec=A:GetSpec() end
        if event=="PLAYER_LOGOUT" then
            if self.queued then self.queued:Cancel();self.queued=nil end
            if not self.reading and not self.writing and not A.Apply.op then self:ObserveMacros();self:ObserveSlots() end
            if A.Apply.InvalidateCurrent then A.Apply:InvalidateCurrent(event) end
            return
        end
        if currentEvents[event] and A.Apply.InvalidateCurrent then A.Apply:InvalidateCurrent(event) end
        if event=="PLAYER_LEAVING_WORLD" then
            if self.queued then self.queued:Cancel();self.queued=nil end
            return
        end
        if (event=="PLAYER_ENTERING_WORLD" or event=="ACTIVE_PLAYER_SPECIALIZATION_CHANGED") and self.observedSpec~=A:GetSpec() then
            self.observedSpec=A:GetSpec();self.pendingSpec=self.observedSpec
            if self.slotDirtySpec and self.slotDirtySpec~=self.observedSpec then self.slotDirty=nil;self.slotDirtySpec=nil end
            local state=self:Spec(self.observedSpec)
            self.resumeFailed=state and state.pendingBars and true or nil
        end
        if event=="UPDATE_MACROS" then
            self.macroDirty=true;self:ObserveMacros()
            if self.macroDirty and not InCombatLockdown() then self:QueueObservation() end
            return
        end
        -- Talent/config notices invalidate matching state, not action slots.
        -- Real edits blocked by combat/native writes stay dirty until a later
        -- safe boundary; the timer never requeues itself or polls native state.
        if InCombatLockdown() then return end
        if event=="CURSOR_CHANGED" then
            if self.pendingSpec and not self.resumeFailed then self:QueueObservation() end
            return
        end
        if self.slotDirty or self.macroDirty or self.pendingSpec or self.macroRevision~=A.Macros.revision then self:QueueObservation() end
    end)
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
