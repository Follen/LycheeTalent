local A={GetSpec=function()return 62 end,Apply={}}
time=function()return 1 end
local combat=false
InCombatLockdown=function()return combat end
UnitClass=function()return "Mage","MAGE" end
C_SpecializationInfo={GetSpecialization=function()return 1 end}
assert(loadfile("addon/LycheeTalent/Storage.lua"))("LycheeTalent",A)
assert(loadfile("addon/LycheeTalent/TalentEx.lua"))("LycheeTalent",A)
A.Store:Init()
A.Talents={Validate=function(_,code)
 code=code:gsub("%s","")
 if code=="bad" then return nil,"BAD_CODE" end
 return code,code=="other" and 63 or 62
end}
local ok,why=A.TalentEx:Import();assert(not ok and why=="TEX_UNAVAILABLE")
TalentLoadoutEx={MAGE={[1]={
 [1]={name="Group"},[3]={name=" Alpha ",text="code",icon=123},
 [4]={name="Alpha",text=" code "},[5]={name="Alpha",text="different"},
 [6]={name="Beta",text="code",icon="Interface\\Icons\\Spell"},
 [7]={name="Old",text="legacy",isLegacy=true},[8]={name="Broken",text="bad"},
 [9]={name="Wrong",text="other"},[10]={name="",text="code"},[11]=false,
 },[2]={{name="Other spec",text="code"}}},WARRIOR={[1]={{name="Other class",text="code"}}}}
local source=TalentLoadoutEx.MAGE[1]
local scan=assert(A.TalentEx:Inspect())
assert(scan.state=="ready" and scan.total==3 and #scan.pending==3 and scan.invalid==5)
assert(#A.Store.builds==0 and not A.Store.db.talentExImports,"inspection is read-only")
local result=assert(A.TalentEx:Import())
assert(result.imported==3 and result.duplicate==1 and result.invalid==5 and result.groups==1)
assert(#A.Store.builds==3 and A.Store.builds[1].icon==123)
assert(A.Store.builds[3].icon==source[6].icon and A.Store.builds[1].source=="user")
assert(source[3].name==" Alpha " and source[4].text==" code ","external data unchanged")
result=assert(A.TalentEx:Import());assert(result.imported==0 and result.duplicate==4)
scan=assert(A.TalentEx:Inspect());assert(scan.state=="imported" and #scan.pending==0 and scan.matched==3)
source[6].text="changed"
scan=assert(A.TalentEx:Inspect());assert(scan.state=="updates" and #scan.pending==1,"same-count content changes are detected")
source[6].text="code"
assert(A.Store:Delete(A.Store.builds[1].id))
scan=assert(A.TalentEx:Inspect());assert(scan.state=="updates" and #scan.pending==1,"deleted local builds can be reimported")
result=assert(A.TalentEx:Import());assert(result.imported==1)
combat=true;ok,why=A.TalentEx:Import();assert(not ok and why=="COMBAT");combat=false
A.Apply.op={};ok,why=A.TalentEx:Import();assert(not ok and why=="APPLY_BUSY");A.Apply.op=nil
A.Store.readonly=true;ok,why=A.TalentEx:Import();assert(not ok and why=="SCHEMA");A.Store.readonly=false
TalentLoadoutEx.MAGE[1]={{name="New",text="new"},{name="Next",text="next"}}
A.Store:Init()
scan=assert(A.TalentEx:Inspect());assert(scan.state=="updates" and #scan.pending==2,"history survives reinitialization and full source replacement")
for i=#A.Store.builds+1,999 do A.Store.builds[i]={name="filler",code="filler",specID=62} end
result=assert(A.TalentEx:Import());assert(result.imported==1 and result.remaining==1 and result.reason=="CAPACITY")
assert(#A.Store.builds==1000)
scan=assert(A.TalentEx:Inspect());assert(scan.state=="updates" and #scan.pending==1,"partial imports remain actionable")
TalentLoadoutEx.MAGE[1]={{name="Group"},{name="Old",text="old",isLegacy=true},{name="Broken",text="bad"}}
scan=assert(A.TalentEx:Inspect());assert(scan.state=="empty" and #scan.pending==0,"invalid data never presents a permanent update")
print("PASS Talent EX: read-only differences, import states, sparse rows, scope, validation, duplicates, icons, source preservation, guards and partial capacity")
