local _,A=...
local X={revision="20260927-clean2"}
A.Apply=X
function X:GuardCreation(frame)
    if not frame or not frame.IsEventRegistered then return end
    self.creationGuard={frame=frame,registered=frame:IsEventRegistered("TRAIT_CONFIG_CREATED")}
    frame:UnregisterEvent("TRAIT_CONFIG_CREATED")
    if not self.guardHooked then
        self.guardHooked=true
        frame:HookScript("OnShow",function()
            if X.creationGuard and X.creationGuard.frame==frame then
                X.creationGuard.registered=true
                frame:UnregisterEvent("TRAIT_CONFIG_CREATED")
            end
        end)
    end
end
function X:ReleaseCreationGuard()
    local guard=self.creationGuard; self.creationGuard=nil
    if guard and guard.registered and guard.frame:IsShown() then
        guard.frame:RegisterEvent("TRAIT_CONFIG_CREATED")
        if guard.frame.RefreshLoadoutOptions then pcall(guard.frame.RefreshLoadoutOptions,guard.frame) end
    end
end
local function configExists(id,spec)
    for _,v in ipairs(C_ClassTalents.GetConfigIDsBySpecID(spec) or {}) do if v==id then return true end end
    return false
end
function X:PendingState(spec,active)
    local char=A.Store.character
    local r=char.recovery
    if not r or (r.status~="interrupted" and r.status~="active") then return nil,"no-interrupted-operation" end
    if r.spec~=spec then return nil,"different-specialization" end
    if not r.targetConfig or not configExists(r.targetConfig,spec) then return nil,"missing-target" end
    local info=C_Traits.GetConfigInfo(r.targetConfig)
    local ownedName=r.targetName
    if not ownedName or not info or info.name~=ownedName or info.type~=Enum.TraitConfigType.Combat then return nil,"target-identity-changed" end
    -- Ownership describes what our last native call staged, not which build
    -- the user is choosing now. A different dungeon/mode can replace our draft.
    local entries=r.pendingEntries or (r.targetCode and A.Talents:Entries(r.targetCode))
    if not entries then return nil,"missing-draft-snapshot" end
    local matches,difference=A.Talents:Matches(active,entries)
    if not matches and r.pendingEntries and r.targetCode then
        -- Async loading may have completed after the immediate snapshot.
        local complete=A.Talents:Entries(r.targetCode)
        if complete then matches,difference=A.Talents:Matches(active,complete) end
    end
    if not matches then return nil,"draft-changed",difference end
    return r
end
function X:CancelPending(ticket)
    if self.pendingTicket==ticket then self.pendingTicket=nil end
end
function X:ConfirmPending(ticket)
    if not ticket or self.pendingTicket~=ticket then return nil,"PENDING_CHANGED" end
    self.pendingTicket=nil
    ticket.accepted=true
    return self:Start(ticket.build,ticket.shared,ticket)
end
function X:RememberPending(op,active)
    if self.op==op and not InCombatLockdown() and C_Traits.ConfigHasStagedChanges(active) then
        -- Only immediately after our native calls, never arbitrary later edits.
        local ok,entries=pcall(A.Talents.ReadEntries,A.Talents,active)
        if ok and entries then op.pendingEntries=entries; A.Store.character.recovery.pendingEntries=entries end
    end
end
function X:ResetPending(active,entries)
    if not C_Traits.RollbackConfig then return nil,"APPLY_UNAVAILABLE" end
    if not A.Talents:Matches(active,entries) then return nil,"PENDING_CHANGED" end
    local op=self.op
    self.preparing=true
    if op then op.inNativeCall=true end
    local ok,result=pcall(C_Traits.RollbackConfig,active)
    self.preparing=nil
    if op then op.inNativeCall=nil end
    if not ok or not result or C_Traits.ConfigHasStagedChanges(active) then return nil,"ROLLBACK_FAILED" end
    return true
end
function X:CurrentBuildID()
    local saved=A.Store.character.applied
    if not saved or self.op or saved.spec~=A:GetSpec() then return end
    if C_ClassTalents.GetStarterBuildActive() then return end
    local binding,info=A.ActionBars:Working(saved.spec)
    if not binding or binding.id~=saved.config or info.usesSharedActionBars then return end
    local build=A.Catalog:Find(saved.id)
    if not build or A.Talents:Code(build)~=saved.code then return end
    local active=C_ClassTalents.GetActiveConfigID()
    if active and not C_Traits.ConfigHasStagedChanges(active)
        and C_ClassTalents.GetLastSelectedSavedConfigID(saved.spec)==binding.id
        and A.Talents:Matches(active,saved.entries) then return saved.id end
end
function X:Finish(ok,key)
    local op=self.op
    if not op then return end
    if self.timer then self.timer:Cancel();self.timer=nil end
    if self.nextStep then self.nextStep:Cancel();self.nextStep=nil end
    if self.events then self.events:UnregisterAllEvents() end
    self.op=nil;self:ReleaseCreationGuard()
    local char=A.Store.character
    char.lastAttempt={revision=self.revision,time=time(),buildID=op.buildID,spec=op.spec,
        shared=op.shared,stage=op.stage,slot=op.failedSlot,luaError=op.luaError,
        reason=key or (ok and "APPLY_SUCCESS" or "APPLY_FAILED")}
    -- A failed initial capture must not destroy an earlier recovery backup.
    if op.recovery and char.recovery==op.recovery then
        char.recovery.status=ok and "complete" or "interrupted"
        char.recovery.reason=char.lastAttempt.reason
        char.recovery.targetConfig=op.target
        char.recovery.targetName=op.targetName
        char.recovery.stage=op.stage
    end
    A:Message(char.lastAttempt.reason)
    if ok and A.Reminders and A.Reminders.enabled then A.Reminders:Check() end
    if A.UI.frame and A.UI.frame:IsShown() then
        A.UI:Refresh()
        if ok and A.UI.ShowApplySuccess then A.UI:ShowApplySuccess(op.buildID,op.startedAt) end
    end
end
function X:CheckContext()
    local op=self.op
    if not op then return end
    if InCombatLockdown() then self:Finish(false,"APPLY_COMBAT");return end
    if A:GetSpec()~=op.spec then self:Finish(false,"APPLY_SPEC_CHANGED");return end
    return true
end
function X:Defer(fn,delay)
    if self.nextStep then return end
    local op=self.op
    self.nextStep=C_Timer.NewTimer(delay or 0,function()
        self.nextStep=nil
        if self.op~=op or not self:CheckContext() then return end
        local ok,err=pcall(fn)
        if not ok and self.op==op then
            op.luaError=tostring(err):sub(1,240)
            if op.recovery then op.recovery.luaError=op.luaError end
            self:Finish(false,"APPLY_FAILED")
        end
    end)
end
function X:LoadNative(id,done)
    local op=self.op
    op.loading=id;op.afterLoad=done;op.stage="native-loading";op.inNativeCall=true
    local result=C_ClassTalents.LoadConfig(id,true)
    op.inNativeCall=nil;op.loadResult=result
    if result==Enum.LoadConfigResult.Error then self:Finish(false,"APPLY_FAILED");return end
    if result==Enum.LoadConfigResult.Ready then
        local active=C_ClassTalents.GetActiveConfigID()
        local entries=A.Talents:ReadEntries(active)
        if not entries or not A.Talents:Matches(id,entries) then self:Finish(false,"STAGED_MISMATCH");return end
        op.inNativeCall=true
        local ok=C_ClassTalents.CommitConfig(id)
        op.inNativeCall=nil
        if not ok then self:Finish(false,"COMMIT_FAILED");return end
    end
    self:Advance()
end
function X:PrepareWorking()
    local op=self.op
    local working=A.ActionBars:Working(op.spec)
    if working then
        op.target=working.id;op.targetName=working.name
        self:ConfigureWorking();return
    end
    if not C_ClassTalents.CanCreateNewConfig() then self:Finish(false,"NATIVE_LIMIT");return end
    op.stage="creating";op.name=A.L.TITLE;op.before={}
    for _,id in ipairs(C_ClassTalents.GetConfigIDsBySpecID(op.spec)) do op.before[id]=true end
    self:GuardCreation(A.Talents:Frame())
    op.inNativeCall=true
    local ok=C_ClassTalents.ImportLoadout(C_ClassTalents.GetActiveConfigID(),op.entries,op.name,op.code)
    op.inNativeCall=nil
    if not ok then self:Finish(false,"APPLY_FAILED");return end
    self:Advance()
end
function X:ConfigureWorking()
    local op=self.op
    local info=C_Traits.GetConfigInfo(op.target)
    if not info or info.name~=op.targetName or not configExists(op.target,op.spec) then self:Finish(false,"BARS_CONTEXT");return end
    local state=A.ActionBars:Spec(op.spec)
    op.stage="configuring";op.inNativeCall=true
    state.working=state.working or {id=op.target,name=op.targetName,spec=op.spec}
    if info.name~=A.L.TITLE then
        -- Persist both exact names before the asynchronous native rename.
        state.working.pendingName=A.L.TITLE;op.pendingName=A.L.TITLE
        C_ClassTalents.RenameConfig(op.target,A.L.TITLE)
    end
    info=C_Traits.GetConfigInfo(op.target)
    if not info or info.name~=A.L.TITLE then op.inNativeCall=nil;op.stage="renaming";return end
    op.targetName=info.name;state.working={id=op.target,name=info.name,spec=op.spec}
    -- All managed layouts, including the default profile, live in one isolated
    -- native bar set. Loading a plugin profile never overwrites native shared bars.
    if info.usesSharedActionBars then C_ClassTalents.SetUsesSharedActionBars(op.target,false) end
    op.inNativeCall=nil
    if C_Traits.GetConfigInfo(op.target).usesSharedActionBars then op.stage="bar-mode";return end
    self:ActivateWorking()
end
function X:ActivateWorking()
    local op=self.op
    -- The remembered config may still point at our loadout while Starter is
    -- active. Always complete a native load before leaving Starter in that case.
    if not C_ClassTalents.GetStarterBuildActive() and C_ClassTalents.GetLastSelectedSavedConfigID(op.spec)==op.target then
        self:StageWorking()
    else self:LoadNative(op.target,function()self:StageWorking()end) end
end
function X:MatchesWorking(op,active)
    if not A.Talents:Matches(active,op.entries) then return false end
    -- Server-derived free ranks may be encoded as purchased in imported data,
    -- but omitted by saved configs. Compare the saved config with the verified
    -- active tree's canonical representation, not the imported representation.
    local canonical=A.Talents:ReadEntries(active)
    return canonical and A.Talents:Matches(op.target,canonical)
end
function X:StageWorking()
    local op=self.op
    if not self:CheckContext() then return end
    local active=C_ClassTalents.GetActiveConfigID()
    if C_Traits.ConfigHasStagedChanges(active) then self:Finish(false,"PENDING");return end
    if C_ClassTalents.GetStarterBuildActive() then
        -- Blizzard's LoadConfigInternal unflags only after loading completes:
        -- SetStarterBuildActive(false) resets pending changes. Verify the saved
        -- loadout first, then wait for the flag to clear before staging ours.
        local entries=A.Talents:ReadEntries(active)
        if not entries or not A.Talents:Matches(op.target,entries) then self:Finish(false,"STAGED_MISMATCH");return end
        op.stage="leaving-starter";op.inNativeCall=true
        local result=C_ClassTalents.SetStarterBuildActive(false)
        op.inNativeCall=nil
        if result==Enum.LoadConfigResult.Error then self:Finish(false,"STARTER_FAILED");return end
        self:Advance();return
    end
    if self:MatchesWorking(op,active) then
        op.stage="applied"
        self:Defer(function()self:CompleteWorking()end);return
    end
    if self.nativeReadyAt and GetTime()<self.nativeReadyAt then
        self:Defer(function()self:StageWorking()end,self.nativeReadyAt-GetTime());return
    end
    op.stage="staging";op.inNativeCall=true
    local called,ok,why=pcall(A.Talents.StageEntries,A.Talents,active,op.entries)
    if not called or not ok then
        C_Traits.RollbackConfig(active);op.inNativeCall=nil
        self:Finish(false,why or "STAGED_MISMATCH");return
    end
    self:RememberPending(op,active)
    op.stage="applying"
    if C_Traits.ConfigHasStagedChanges(active) then ok=C_ClassTalents.CommitConfig(op.target)
    else ok=C_ClassTalents.SaveConfig(op.target) end
    op.inNativeCall=nil
    if not ok then C_Traits.RollbackConfig(active);self:Finish(false,"COMMIT_FAILED");return end
    self:Advance()
end
function X:CompleteWorking()
    local op=self.op
    local state=A.ActionBars:Spec(op.spec)
    local snapshot,why=A.ActionBars:Get(op.spec,op.buildID,op.shared)
    if not snapshot and not op.shared then
        snapshot,why=A.ActionBars:Get(op.spec,nil,true)
        if snapshot then A.ActionBars:SaveIndependent(op.spec,op.buildID,snapshot) end
    end
    if not snapshot then self:Finish(false,why);return end
    op.stage="action-bars"
    local ok,reason,detail=A.ActionBars:Restore(snapshot)
    if not ok then
        A.Store.character.recovery.actionBars={reason=reason,detail=detail,backup=A.ActionBars.recovery}
        self:Finish(false,reason);return
    end
    local saved,saveReason=A.ActionBars:SaveLayout(op.spec,op.buildID,op.shared,A.ActionBars.verified)
    if not saved then self:Finish(false,saveReason);return end
    state.active={id=op.buildID,shared=op.shared,config=op.target,code=op.code}
    A.Store.character.applied={id=op.buildID,code=op.code,spec=op.spec,config=op.target,shared=op.shared,entries=op.entries}
    A.ActionBars:Track(A.ActionBars.verified)
    local preserved=detail and detail.preservedSlots
    if preserved then
        A.Store.character.recovery.actionBars={reason="BARS_PARTIAL",detail=detail}
    end
    -- Capture, restore, verify and persist have all finished under this op.
    -- Later display notifications are passive and cannot restart cursor work.
    self:Finish(true)
    if preserved then A:Message(string.format(A.L.BARS_PARTIAL,table.concat(preserved,", "))) end
end
function X:Advance()
    local op=self.op
    if not op or op.inNativeCall or not self:CheckContext() then return end
    local active=C_ClassTalents.GetActiveConfigID()
    if op.stage=="renaming" then
        local info=C_Traits.GetConfigInfo(op.target)
        if info and info.name==op.pendingName then
            op.targetName=info.name
            A.ActionBars:Spec(op.spec).working={id=op.target,name=info.name,spec=op.spec}
            self:Defer(function()self:ConfigureWorking()end)
        end
    elseif op.stage=="bar-mode" then
        local info=C_Traits.GetConfigInfo(op.target)
        if info and info.name==op.targetName and not info.usesSharedActionBars then self:Defer(function()self:ActivateWorking()end) end
    elseif op.stage=="creating" and op.target and C_ClassTalents.IsConfigPopulated(op.target) then
        self:Defer(function()self:ConfigureWorking()end)
    elseif op.stage=="native-loading" and not C_Traits.ConfigHasStagedChanges(active) then
        local entries=A.Talents:ReadEntries(active)
        if entries and A.Talents:Matches(op.loading,entries) then
            op.stage="native-loaded"
            C_ClassTalents.UpdateLastSelectedSavedConfigID(op.spec,op.loading)
            self.nativeReadyAt=GetTime()+1
            self:Defer(op.afterLoad,1)
        end
    elseif op.stage=="leaving-starter" and not C_ClassTalents.GetStarterBuildActive()
        and not C_Traits.ConfigHasStagedChanges(active) then
        op.stage="starter-left"
        self:Defer(function()self:StageWorking()end)
    elseif op.stage=="applying" and not C_Traits.ConfigHasStagedChanges(active)
        and self:MatchesWorking(op,active) then
        op.stage="applied"
        self.nativeReadyAt=GetTime()+1
        C_ClassTalents.UpdateLastSelectedSavedConfigID(op.spec,op.target)
        self:Defer(function()self:CompleteWorking()end)
    end
end
function X:OnEvent(event,value)
    local op=self.op
    if not op then return end
    if event=="CONFIG_COMMIT_FAILED" then self:Finish(false,"COMMIT_FAILED");return end
    if event=="STARTER_BUILD_ACTIVATION_FAILED" and op.stage=="leaving-starter" then self:Finish(false,"STARTER_FAILED");return end
    if not self:CheckContext() then return end
    if event=="TRAIT_CONFIG_CREATED" and type(value)=="table" and op.stage=="creating"
        and value.name==op.name and not op.before[value.ID] and value.type==Enum.TraitConfigType.Combat then
        op.target=value.ID;op.targetName=value.name
    end
    self:Advance()
end
function X:Start(build,shared,consent)
    if self.op or self.preparing then return nil,"APPLY_BUSY" end
    if InCombatLockdown() then return nil,"COMBAT" end
    if A.Store.readonly then return nil,"SCHEMA" end
    local code,why=A.Talents:Code(build);if not code then return nil,why end
    local valid,spec=A.Talents:Validate(code);if not valid then return nil,spec end
    local active=C_ClassTalents.GetActiveConfigID()
    if not active or not C_ClassTalents.CanEditTalents() then return nil,"APPLY_UNAVAILABLE" end
    if GetCursorInfo() then return nil,"BARS_CURSOR" end
    local entries=A.Talents:Entries(code);if not entries then return nil,"BAD_CODE" end
    shared=shared==true
    if consent and (self.pendingTicket~=nil or not consent.accepted or consent.spec~=spec or consent.active~=active
        or consent.build.id~=build.id or consent.build.code~=code or consent.shared~=shared) then return nil,"PENDING_CHANGED" end
    if C_Traits.ConfigHasStagedChanges(active) then
        local prior=self:PendingState(spec,active)
        local captured=A.Talents:ReadEntries(active)
        if not prior and not consent then
            local ticket={build={id=build.id,name=build.name,code=code},shared=shared,spec=spec,active=active,entries=captured}
            self.pendingTicket=ticket;return nil,"PENDING",ticket
        end
        if consent and not A.Talents:Matches(active,consent.entries) then return nil,"PENDING_CHANGED" end
        A.Store.character.pendingBackup={code=A.Talents:Export(true),spec=spec,time=time(),manual=consent~=nil}
        local ok,reason=self:ResetPending(active,captured)
        if not ok then return nil,reason end
    end
    self.pendingTicket=nil
    local originalCode=A.Talents:Export();if not originalCode then return nil,"NOT_READY" end
    local selected=C_ClassTalents.GetLastSelectedSavedConfigID(spec)
    local op={buildID=build.id,code=code,entries=entries,spec=spec,shared=shared,stage="capture-bars",
        originalSaved=selected,originalCode=originalCode,previousBuildID=self:CurrentBuildID(),
        previousApplied=A.Store.character.applied,startedAt=GetTime()}
    self.op=op
    if not self.events then
        self.events=CreateFrame("Frame")
        self.events:SetScript("OnEvent",function(_,event,...)
            local ok,err=pcall(X.OnEvent,X,event,...)
            if not ok and X.op then
                local current=X.op;current.luaError=tostring(err):sub(1,240)
                if current.recovery then current.recovery.luaError=current.luaError end
                X:Finish(false,"APPLY_FAILED")
            end
        end)
    end
    for _,event in ipairs({"TRAIT_CONFIG_CREATED","TRAIT_CONFIG_UPDATED","CONFIG_COMMIT_FAILED","STARTER_BUILD_ACTIVATION_FAILED","PLAYER_REGEN_DISABLED","ACTIVE_PLAYER_SPECIALIZATION_CHANGED","ACTIVE_COMBAT_CONFIG_CHANGED","PLAYER_TALENT_UPDATE","SELECTED_LOADOUT_CHANGED"}) do self.events:RegisterEvent(event) end
    self.timer=C_Timer.NewTimer(25,function()if X.op==op then X:Finish(false,"APPLY_TIMEOUT")end end)
    A:Message("APPLYING")
    if A.UI.frame and A.UI.frame:IsShown() then A.UI:Refresh() end
    -- Yield once so Applying can paint before the first cursor-assisted read.
    self:Defer(function()self:CaptureBeforeApply()end)
    return true
end
function X:CaptureBeforeApply()
    local op=self.op
    local spec=op.spec
    local before,reason,slot=A.ActionBars:Capture(spec)
    if not before then
        op.failedSlot=slot;self:Finish(false,reason);return
    end
    local state=A.ActionBars:Spec(spec);if not state then self:Finish(false,"SCHEMA");return end
    if not state.default then
        local ok,err=A.ActionBars:SeedDefault(spec,before,"first-use");if not ok then self:Finish(false,err);return end
    end
    if op.previousBuildID and op.previousApplied then
        local saved,why=A.ActionBars:SaveLayout(spec,op.previousBuildID,op.previousApplied.shared,before)
        if not saved then self:Finish(false,why);return end
    end
    op.stage="preparing"
    op.recovery={revision=self.revision,status="active",spec=spec,code=op.originalCode,bars=before,
        originalSaved=op.originalSaved,targetCode=op.code,buildID=op.buildID,shared=op.shared,time=time()}
    A.Store.character.recovery=op.recovery
    self:Defer(function()self:PrepareWorking()end)
end
function X:Restore()
    local saved=A.Store.character.recovery
    if not saved or not saved.code or saved.spec~=A:GetSpec() then return nil,"NO_RECOVERY" end
    local key="recovery:"..tostring(saved.originalSaved or 0)
    if saved.bars then A.ActionBars:SaveIndependent(saved.spec,key,saved.bars) end
    return self:Start({id=key,name=A.L.RESTORE,code=saved.code},false)
end
