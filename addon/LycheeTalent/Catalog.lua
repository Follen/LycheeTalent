local _,A=...
local C={loaded={},builds={},byID={},scenarios={}}
A.Catalog=C
function C:Load()
    local _,class=UnitClass("player")
    if not self.loaded[class] then
        if InCombatLockdown() then return end
        local name="LycheeTalent_Data_"..class
        if C_AddOns.DoesAddOnExist(name) then
            local loaded=C_AddOns.LoadAddOn(name)
            if not loaded then return end
        end
        self.loaded[class]=true
        local pack=LycheeTalentData and LycheeTalentData[class]
        if pack and type(pack.builds)=="table" then
            self.builds=pack.builds
            for _,b in ipairs(self.builds) do self.byID[b.id]=b end
        end
    end
    self:Localize()
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
        for _,b in ipairs(self.builds) do
            local match=q=="" or b.name:lower():find(q,1,true) or self:Target(b):lower():find(q,1,true) or self:Title(b):lower():find(q,1,true)
            if b.specIndex==specIndex and match and (q~="" or scene==b.scene) then out[#out+1]=b end
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
