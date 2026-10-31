-- A new install may enable the main addon while its own class data stays disabled.
-- Load the real Holy Paladin shard through the production catalog entry point.
local A={GetSpec=function()return 65 end}
UnitClass=function()return "Paladin","PALADIN"end
UnitName=function()return "CurrentPlayer"end
GetLocale=function()return "enUS"end
local combat=false
InCombatLockdown=function()return combat end
C_SpecializationInfo={GetSpecialization=function()return 1 end}
C_ChallengeMode={GetMapTable=function()return {}end}
assert(loadfile("addon/LycheeTalent/Storage.lua"))("LycheeTalent",A)
A.Store.character={};A.Store.db={};A.Store.builds={}
assert(loadfile("addon/LycheeTalent/Scenarios.lua"))("LycheeTalent",A)
local exists,enabled,enableAllowed,oldData=true,false,true,false
local loads,enables=0,0
C_AddOns={
    DoesAddOnExist=function(name)assert(name=="LycheeTalent_Data_PALADIN");return exists end,
    EnableAddOn=function(name,character)
        assert(name=="LycheeTalent_Data_PALADIN","only the current class package may be enabled")
        assert(character=="CurrentPlayer","other characters' enable preferences stay unchanged")
        enables=enables+1;if enableAllowed then enabled=true end
    end,
    LoadAddOn=function(name)
        assert(name=="LycheeTalent_Data_PALADIN");loads=loads+1
        if not enabled then return nil,"DISABLED"end
        if oldData then LycheeTalentData={PALADIN={builds={}}}
        else assert(loadfile("addon/LycheeTalent_Data_PALADIN/Data.lua"))() end
        return true
    end,
}
local function fresh()
    LycheeTalentData=nil;loads=0;enables=0
    assert(loadfile("addon/LycheeTalent/Catalog.lua"))("LycheeTalent",A)
    return A.Catalog
end
local C=fresh();C:Load()
assert(#C:Heroes(65)==2,"disabled current-class data must load instead of two unavailable hero buttons")
assert(enables==1 and loads==2,"enable once and retry the failed native load once")
local results={};C:Query(65,"mythic","builtin","",nil,nil,results)
assert(#results==8,"the shipped Holy Paladin recommendations must appear")
for i=1,100 do C:Load()end
assert(loads==2 and enables==1,"successful loads stay cached")

enabled=false;enableAllowed=false;C=fresh()
local ok,why=C:Load()
assert(not ok and why=="DISABLED" and C.loadFailure=="DISABLED","a persistent native failure retains its real reason")
assert(not C.loaded.PALADIN and enables==1 and loads==2)
enableAllowed=true;C:Load();assert(#C:Heroes(65)==2 and not C.loadFailure,"a corrected failure is retryable")

exists=false;enabled=false;C=fresh();ok,why=C:Load()
assert(not ok and why=="MISSING" and C.loadFailure=="MISSING" and not C.loaded.PALADIN)
assert(loads==0 and enables==0,"missing packages are not enabled or reported loaded")
exists=true;combat=true;C=fresh();ok,why=C:Load()
assert(not ok and why=="COMBAT" and loads==0 and enables==0,"combat defers package loading and enable changes")
combat=false;C:Load();assert(#C:Heroes(65)==2)

enabled=true;oldData=true;C=fresh();ok,why=C:Load()
assert(not ok and why=="INCOMPLETE" and not C.loaded.PALADIN,"older shards without hero pairs need a complete update")
oldData=false;C:Load();assert(#C:Heroes(65)==2 and not C.loadFailure)
print("PASS catalog loading: disabled current class, real Paladin recommendations, character scope, native failure, missing/old data, combat and retry")
