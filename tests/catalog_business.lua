-- Published catalog contracts used by both the default list and reminders.
local A={}
assert(loadfile('addon/LycheeTalent/Scenarios.lua'))('LycheeTalent',A)
local scenarios,raid={},{}
for _,scene in ipairs(A.Scenarios) do
    assert(not scenarios[scene.id],'duplicate scenario '..scene.id)
    scenarios[scene.id]=scene
    if scene.scene=='raid' and scene.journalID>0 then raid[#raid+1]=scene end
end
table.sort(raid,function(a,b)
    if a.raidOrder~=b.raidOrder then return a.raidOrder<b.raidOrder end
    return a.bossOrder<b.bossOrder
end)
local expected={'3470','3445','3497','3455','3420','3421','3429','3492','3379'}
assert(#raid==#expected,'published raid boss count')
for i,id in ipairs(expected) do assert(raid[i].id==id,'raid boss order at '..i) end

local total=0
for _,class in ipairs({'DEATHKNIGHT','DEMONHUNTER','DRUID','EVOKER','HUNTER','MAGE','MONK','PALADIN','PRIEST','ROGUE','SHAMAN','WARLOCK','WARRIOR'}) do
    assert(loadfile('addon/LycheeTalent_Data_'..class..'/Data.lua'))()
    local pack=assert(LycheeTalentData[class],'missing class pack '..class)
    local defaults={}
    for _,build in ipairs(pack.builds) do
        total=total+1
        local scene=assert(scenarios[tostring(build.scenarioID)],'unknown scenario '..build.id)
        assert(build.scene==scene.scene,'scene mismatch '..build.id)
        assert((scene.scene=='mythic' and type(scene.mapID)=='number' and scene.mapID>0) or
            (scene.scene=='raid' and type(scene.journalID)=='number' and scene.journalID>0),
            'published build has no supported arrival context '..build.id)
        if build.kind~='popular' then
            assert((build.scene=='mythic' and build.kind=='highest') or
                (build.scene=='raid' and build.kind=='ranked'),'unexpected default kind '..build.id)
            local key=build.specIndex..':'..build.scenarioID..':'..(build.difficulty or 0)
            assert(not defaults[key],'duplicate default '..class..':'..key)
            defaults[key]=true
        end
    end
end
assert(total>0,'empty published catalog')
print('PASS published catalog: '..total..' builds, unique defaults, valid scenes and raid order')
