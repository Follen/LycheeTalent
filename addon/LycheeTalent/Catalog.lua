local _,A=...
local C={loaded={},builds={},byID={},scenarios={}}
A.Catalog=C
local function loadFailed(self,reason)
    self.loadFailure=reason
    return false,reason
end
function C:Load()
    local _,class=UnitClass("player")
    if not self.loaded[class] then
        if InCombatLockdown() then return loadFailed(self,"COMBAT") end
        local name="LycheeTalent_Data_"..class
        if not C_AddOns.DoesAddOnExist(name) then return loadFailed(self,"MISSING") end
        local loaded,reason=C_AddOns.LoadAddOn(name)
        if not loaded and reason=="DISABLED" then
            -- This shard belongs to the enabled main addon. Enable only the
            -- current class for this character, then retry the native load once.
            C_AddOns.EnableAddOn(name,UnitName("player"))
            loaded,reason=C_AddOns.LoadAddOn(name)
        end
        if not loaded then return loadFailed(self,reason or "LOAD_FAILED") end
        local pack=LycheeTalentData and LycheeTalentData[class]
        if not pack or type(pack.builds)~="table" or type(pack.heroTrees)~="table" then return loadFailed(self,"INCOMPLETE") end
        self.builds=pack.builds;self.heroTrees=pack.heroTrees
        for _,b in ipairs(self.builds) do self.byID[b.id]=b end
        self.loaded[class]=true
    end
    self.loadFailure=nil
    self:Localize()
    return true
end
function C:Localize()
    if self.localized then return end
    self.localized=true
    local maps={}
    if C_ChallengeMode and C_ChallengeMode.GetMapTable then
        for _,id in ipairs(C_ChallengeMode.GetMapTable() or {}) do
            local name,_,_,icon,_,mapID=C_ChallengeMode.GetMapUIInfo(id)
            if icon and name then maps[icon]={name=name,mapID=mapID} end
        end
    end
    for _,s in ipairs(A.Scenarios or {}) do
        s.label=GetLocale()=="zhCN" and s.zhCN or nil
        if s.scene=="mythic" and maps[s.icon] then s.label=maps[s.icon].name; s.mapID=maps[s.icon].mapID
        elseif s.scene=="raid" and s.journalID and s.journalID>0 and EJ_GetEncounterInfo then
            local ok,name=pcall(EJ_GetEncounterInfo,s.journalID); if ok and name then s.label=name end
        end
        s.label=s.label or s.name; self.scenarios[s.id]=s
    end
end
-- Hero choices come from the shipped specialization pair, never popularity.
function C:Heroes(specID)
    if A.GetSpec and specID~=A:GetSpec() then return {} end
    local index=C_SpecializationInfo.GetSpecialization()
    return self.heroTrees and self.heroTrees[index] or {}
end
function C:SelectedHero(specID)
    local heroes=self:Heroes(specID)
    local selected=A.Store:GetHero(specID)
    if selected~=nil then
        for _,hero in ipairs(heroes) do if hero.id==selected then return selected end end
        return nil,"HERO_UNKNOWN"
    end
    if heroes[1] then
        local active=C_ClassTalents and C_ClassTalents.GetActiveHeroTalentSpec and C_ClassTalents.GetActiveHeroTalentSpec()
        if issecretvalue and issecretvalue(active) then active=nil end
        local initial=heroes[1].id
        for _,hero in ipairs(heroes) do if hero.id==active then initial=active;break end end
        A.Store:SetHero(specID,initial)
        return initial
    end
    return nil,"HERO_MISSING"
end
function C:HeroInfo(hero)
    local cached=self.heroInfo and self.heroInfo[hero.id]
    if cached then return cached.name,cached.atlas end
    local active=C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    if active and C_Traits and C_Traits.GetSubTreeInfo then
        local ok,info=pcall(C_Traits.GetSubTreeInfo,active,hero.id)
        local name=ok and info and info.name
        local atlas=ok and info and info.iconElementID
        if atlas and (issecretvalue and issecretvalue(atlas)) then atlas=nil end
        if type(atlas)~="string" and type(atlas)~="number" then atlas=nil end
        if name and not (issecretvalue and issecretvalue(name)) and type(name)=="string" and name~="" then
            -- Only keep the two display fields, not the native subtree table.
            -- Incomplete metadata stays retryable when the talent UI is ready.
            if atlas then
                self.heroInfo=self.heroInfo or {};self.heroInfo[hero.id]={name=name,atlas=atlas}
            end
            return name,atlas
        end
    end
    return hero.name or tostring(hero.id)
end
function C:HeroName(hero) return (self:HeroInfo(hero)) end
function C:SetHero(specID,heroTree) return A.Store:SetHero(specID,heroTree) end
function C:Target(b)
    local s=b.scenarioID and self.scenarios[tostring(b.scenarioID)]
    return s and s.label or b.target or ""
end
function C:Title(b)
    if b.source~="builtin" then return b.name end
    return self:Target(b)
end
function C:Query(specID,scene,source,query,target,difficulty,out)
    A.Store:Query(specID,scene,source,query,out)
    local specIndex=C_SpecializationInfo.GetSpecialization()
    local q=(query or ""):lower()
    if source~="user" and scene~="mine" then
        local hero=self:SelectedHero(specID)
        local seen={}
        for _,b in ipairs(self.builds) do
            local match=q=="" or b.name:lower():find(q,1,true) or self:Target(b):lower():find(q,1,true) or self:Title(b):lower():find(q,1,true)
            local kind=(b.scene=="mythic" and b.kind=="highest") or (b.scene=="raid" and b.kind=="ranked")
            local key=b.scene..":"..tostring(b.scenarioID)..":"..tostring(b.difficulty or 0)
            if hero and b.heroTree==hero and kind and b.specIndex==specIndex and match and (q~="" or scene==b.scene) and not seen[key] then
                out[#out+1]=b;seen[key]=true
            end
        end
    end
    for i=#out,1,-1 do
        local b=out[i]
        if (target and q=="" and tostring(b.scenarioID or "")~=target) or
            (difficulty and b.scene=="raid" and b.source=="builtin" and b.difficulty~=difficulty) then table.remove(out,i) end
    end
    table.sort(out,function(a,b)
        local an,bn=self:Title(a):lower(),self:Title(b):lower()
        if q~="" then
            local ae,be=an==q,bn==q; if ae~=be then return ae end
            local ap,bp=an:sub(1,#q)==q,bn:sub(1,#q)==q; if ap~=bp then return ap end
        end
        if a.source~=b.source then return a.source=="builtin" end
        if a.source=="user" then return A.Store:OrderLess(a,b) end
        if a.source=="builtin" and a.scene=="raid" and b.scene=="raid" then
            local sa,sb=self.scenarios[tostring(a.scenarioID)],self.scenarios[tostring(b.scenarioID)]
            local ar,br=sa and sa.raidOrder or 999,sb and sb.raidOrder or 999
            if ar~=br then return ar<br end
            local ao,bo=sa and sa.bossOrder or 999,sb and sb.bossOrder or 999
            if ao~=bo then return ao<bo end
        end
        if (a.kind=="popular")~=(b.kind=="popular") then return b.kind=="popular" end
        return tostring(a.id)<tostring(b.id)
    end)
end
function C:Find(id) return self.byID[id] or A.Store:Find(id) end
function C:SourceURL(b)
    if not b or type(b.report)~="string" or not b.report:match("^[%w]+$") then return end
    local fight=tonumber(b.fight)
    if not fight or fight<1 or fight~=math.floor(fight) then return end
    return "https://www.warcraftlogs.com/reports/"..b.report.."#fight="..fight
end
