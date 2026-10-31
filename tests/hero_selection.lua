local A={GetSpec=function()return 71 end}
C_SpecializationInfo={GetSpecialization=function()return 1 end}
assert(loadfile("addon/LycheeTalent/Storage.lua"))("LycheeTalent",A)
assert(loadfile("addon/LycheeTalent/Catalog.lua"))("LycheeTalent",A)
local S,C=A.Store,A.Catalog
S.character={};S.db={};S.builds={{id=1,name="Personal",code="x",specID=71,scene="mythic",source="user"}}
C.heroTrees={[1]={{id=60,name="Slayer"},{id=62,name="Colossus"}},[2]={{id=61,name="Other"}}}
local function build(id,scene,target,hero,kind,difficulty)
 return {id=id,name=id,source="builtin",specIndex=1,scene=scene,scenarioID=target,heroTree=hero,kind=kind,difficulty=difficulty}
end
C.builds={build("slayer","mythic","one",60,"highest"),build("colossus","mythic","one",62,"highest"),
 build("popular","mythic","one",60,"popular"),build("duplicate","mythic","one",60,"highest"),
 build("unknown","mythic","one",999,"highest"),build("slayer-raid","raid","boss",60,"ranked",5),
 build("colossus-raid","raid","boss",62,"ranked",5),build("heroic","raid","boss",62,"ranked",4)}
C_ClassTalents={GetActiveHeroTalentSpec=function()return 62 end}
assert(C:SelectedHero(71)==62 and S:GetHero(71)==62,"initial native hero is remembered")
C_ClassTalents.GetActiveHeroTalentSpec=function()return 60 end
assert(C:SelectedHero(71)==62,"native changes cannot override remembered selection")
S.character.heroChoices=nil;C_ClassTalents.GetActiveHeroTalentSpec=function()return 999 end
local out={}
local function query(scene,difficulty)C:Query(71,scene,"builtin","",nil,difficulty,out);return out end
assert(C:SelectedHero(71)==60 and #query("mythic")==1 and out[1].id=="slayer")
assert(C:SetHero(71,62));assert(#query("mythic")==1 and out[1].id=="colossus")
assert(#query("raid",5)==1 and out[1].id=="colossus-raid","raid follows same specialization preference")
assert(#query("raid",4)==1 and out[1].id=="heroic")
C:Query(71,"mine","user","",nil,nil,out);assert(#out==1 and out[1].id==1,"personal builds are never filtered")
assert(not C:SetHero(71,999) and S:GetHero(71)==62)
C.heroTrees[1][2].id=63
assert(C:SelectedHero(71)==nil and #query("mythic")==0,"unknown persisted choice must not borrow another hero")
C.heroTrees[1][2].id=62;C.builds[2].heroTree=60
assert(#query("mythic")==0,"known hero without data remains empty")
S.character.heroChoices["72"]=61;A.GetSpec=function()return 72 end;C_SpecializationInfo.GetSpecialization=function()return 2 end
assert(C:SelectedHero(72)==61 and S:GetHero(71)==62,"choices are specialization-scoped")
A.GetSpec=function()return 71 end;C_SpecializationInfo.GetSpecialization=function()return 1 end
assert(C:SelectedHero(71)==62,"returning specialization retains selection")
print("PASS hero selection: legal pairs, remembered spec scope, shared scene preference, strict filtering, missing data, personal isolation")
