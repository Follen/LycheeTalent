local _,A=...
local R={radius=120,seen={},order={},maxSeen=64}
A.Reminders=R
local function plain(v) return not (issecretvalue and issecretvalue(v)) end
local function number(v) return plain(v) and type(v)=="number" and v==v end
function R:Configured(build)
    if type(build)~="table" or build.source~="user" or build.remind~=true or type(build.contexts)~="table" then return false end
    for id,enabled in pairs(build.contexts) do if enabled==true and A.Catalog.scenarios[id] then return true end end
    return false
end
function R:Hide()
    self.visible=nil
    if A.UI.reminder then A.UI.reminder:Hide() end
end
function R:Remember(key)
    if self.seen[key] then return end
    self.seen[key]=true;self.order[#self.order+1]=key
    if #self.order>self.maxSeen then self.seen[table.remove(self.order,1)]=nil end
end
function R:Context()
    if InCombatLockdown() then return end
    local _,kind,_,_,_,_,_,instance=GetInstanceInfo()
    if not plain(kind) or not number(instance) then return end
    if kind~="party" and kind~="raid" then return nil,"outside" end
    if kind=="party" then
        for _,s in ipairs(A.Scenarios) do if s.scene=="mythic" and s.mapID==instance then return s.id,instance end end
        return nil,instance
    end
    local map=C_Map.GetBestMapForUnit("player")
    if not number(map) or map<=0 then return nil,instance end
    local point=C_Map.GetPlayerMapPosition(map,"player")
    if not point or not plain(point) then return nil,instance end
    local x,y=point:GetXY()
    local width,height=C_Map.GetMapWorldSize(map)
    if not number(x) or not number(y) or not number(width) or not number(height) or width<=0 or height<=0 then return nil,instance end
    local encounters=C_EncounterJournal.GetEncountersOnMap(map)
    if type(encounters)~="table" or #encounters>64 then return nil,instance end
    local best,first,second=nil,math.huge,math.huge
    for _,encounter in ipairs(encounters) do
        if number(encounter.encounterID) and number(encounter.mapX) and number(encounter.mapY) then
            local distance=((x-encounter.mapX)*width)^2+((y-encounter.mapY)*height)^2
            if distance<first then best=encounter.encounterID;second=first;first=distance
            elseif distance<second then second=distance end
        end
    end
    -- Do not guess when two boss markers overlap or the player is elsewhere.
    if not best or first>self.radius^2 or second-first<30^2 then return nil,instance end
    for _,s in ipairs(A.Scenarios) do if s.scene=="raid" and s.journalID==best then return s.id,instance end end
    return nil,instance
end
function R:UpdateMovementEvent()
    if not self.events then return end
    local _,kind=GetInstanceInfo()
    if plain(kind) and kind=="raid" and self.hasRaid and not InCombatLockdown() then self.events:RegisterEvent("PLAYER_STOPPED_MOVING")
    else self.events:UnregisterEvent("PLAYER_STOPPED_MOVING") end
end
function R:Candidates(context,spec)
    local builds={}
    for _,b in ipairs(A.Store.builds) do
        if b.specID==spec and self:Configured(b) and b.contexts[context]==true then builds[#builds+1]=b end
    end
    local index=C_SpecializationInfo.GetSpecialization()
    local _,_,difficulty=GetInstanceInfo()
    local raidDifficulty=number(difficulty) and (difficulty==16 and 5 or difficulty==15 and 4) or nil
    local default
    for _,b in ipairs(A.Catalog.builds) do
        if b.specIndex==index and tostring(b.scenarioID)==context and
            (b.scene~="raid" or (raidDifficulty and b.difficulty==raidDifficulty)) then
            if (b.scene=="mythic" and b.kind=="highest") or (b.scene=="raid" and b.kind=="ranked") then default=b end
        end
    end
    -- A single default WCL recommendation; personal associations stay available alongside it.
    if default then builds[#builds+1]=default end
    return builds
end
function R:Check()
    if not self.enabled then return end
    self:UpdateMovementEvent()
    if InCombatLockdown() then self:Hide();return end
    local context,instance=self:Context()
    if instance=="outside" then self.seen={};self.order={};self.instance=nil;self:Hide();return end
    if self.instance~=instance then self.seen={};self.order={};self.instance=instance end
    if not context then self:Hide();return end
    local spec=A:GetSpec()
    if not number(spec) or spec<=0 then self:Hide();return end
    local key=tostring(spec)..":"..tostring(instance)..":"..context
    if self.visible and self.visible.key~=key then self:Hide() end
    if A.Apply.op then self:Hide();return end
    A.Catalog:Load()
    local current=A.Apply:CurrentBuildID()
    if self.visible then
        for _,build in ipairs(self.visible.builds) do if build.id==current then self:Hide();return end end
    end
    if self.seen[key] then return end
    local builds=self:Candidates(context,spec)
    for _,b in ipairs(builds) do if current==b.id then self:Remember(key);self:Hide();return end end
    if #builds==0 then self:Hide();return end
    self:Remember(key)
    self.visible={key=key,id=context,spec=spec,builds=builds}
    A.UI:ShowReminder(self.visible)
end
function R:Apply(buildID)
    local prompt=self.visible
    if not prompt or InCombatLockdown() or prompt.spec~=A:GetSpec() then return nil,"COMBAT" end
    local context=self:Context()
    local build
    if context==prompt.id and A.Store.db.remindersEnabled~=false then
        for _,candidate in ipairs(self:Candidates(context,A:GetSpec())) do if candidate.id==buildID then build=candidate;break end end
    end
    if not build then self:Hide();return nil,"REMINDER_CHANGED" end
    local shared=(A.Store.character.modes or {})[tostring(buildID)]==true
    local ok,reason,ticket=A.Apply:Start(build,shared)
    if ok then self:Hide()
    elseif reason=="PENDING" and ticket then self:Hide();A.UI:ConfirmPending(ticket,A.Catalog:Title(build)) end
    return ok,reason
end
function R:RefreshSettings()
    local enabled=A.Store.db.remindersEnabled~=false
    self.enabled=enabled;self.hasRaid=enabled
    if not enabled then
        if self.events then self.events:UnregisterAllEvents() end
        if self.timer then self.timer:Cancel();self.timer=nil end
        self.seen={};self.order={};self:Hide();return
    end
    A.Catalog:Localize()
    if not self.events then
        self.events=CreateFrame("Frame")
        self.events:SetScript("OnEvent",function(_,event,encounter,_,_,_,success)
            if event=="PLAYER_REGEN_DISABLED" then
                if R.visible then
                    R.seen[R.visible.key]=nil
                    for i=#R.order,1,-1 do if R.order[i]==R.visible.key then table.remove(R.order,i) end end
                end
                R:Hide();R:UpdateMovementEvent();return
            end
            if event=="ENCOUNTER_END" and plain(success) and success==1 and number(encounter) then
                for _,s in ipairs(A.Scenarios) do if s.scene=="raid" and tonumber(s.id)==encounter and R.instance then R:Remember(tostring(A:GetSpec())..":"..tostring(R.instance)..":"..s.id) end end
            end
            if not R.timer then R.timer=C_Timer.NewTimer(.2,function()R.timer=nil;R:Check()end) end
        end)
    end
    for _,event in ipairs({"PLAYER_ENTERING_WORLD","ZONE_CHANGED_NEW_AREA","ZONE_CHANGED","ZONE_CHANGED_INDOORS","ACTIVE_PLAYER_SPECIALIZATION_CHANGED","PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED","ENCOUNTER_END"}) do self.events:RegisterEvent(event) end
    self:Check()
end
