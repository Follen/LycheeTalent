local A={}
assert(loadfile("addon/LycheeTalent/Storage.lua"))("LycheeTalent",A)
local S=A.Store;local schema="Lychee.Talent.Schema.V2:"
time=function()return 1 end
GetMacroInfo=function()error("Store initialization must not recover old macros")end
CreateMacro=function()error("cannot create macros during reset")end
EditMacro=function()error("cannot edit macros during reset")end
DeleteMacro=function()error("cannot delete macros during reset")end
C_ClassTalents={GetConfigIDsBySpecID=function()error("cannot adopt old native configs")end,DeleteConfig=function()error("cannot delete native configs")end}
local function account(kind)
 if kind=="nil" then return nil end
 return {schema=kind=="v2" and schema or kind=="v1" and "Lychee.Talent.Schema.V1:" or nil,
  nextID=9,builds={{id=9,name="Saved",code="saved",source="user",specID=71}},remindersEnabled=false,reducedMotion=true,extra="account"}
end
local function character(kind)
 if kind=="nil" then return nil end
 return {schema=kind=="v2" and schema or kind=="v1" and "Lychee.Talent.Schema.V1:" or nil,
  heroChoices={["71"]=60},raidDifficulty=4,actionBars={version=1,specs={[71]={profiles={},working={id=20,name="Player config"}}}},
  nativeMacros={nextID=1,records={["1"]={index=121,native={name="Existing",icon=1,body="/say current"}}}},
  macroPool={{name="LTAB01",body="old"}},recovery={code="old"},extra="character"}
end
for _,a in ipairs({"nil","unmarked","v1","v2"})do
 for _,c in ipairs({"nil","unmarked","v1","v2"})do
  local oldAccount,oldChar=account(a),character(c)
  LycheeTalentDB,LycheeTalentCharacterDB=oldAccount,oldChar
  S.undo={id=999,name="Old undo"};S:Init()
  assert(S.db.schema==schema and S.character.schema==schema and S.undo==nil)
  if a=="v2" then assert(S.db==oldAccount and S.builds[1].id==9 and not S.db.remindersEnabled)
  else assert(S.db~=oldAccount and #S.builds==0 and S.db.nextID==0 and S.db.extra==nil and S.db.remindersEnabled)end
  if c=="v2" then assert(S.character==oldChar and S.character.heroChoices["71"]==60 and S.character.recovery.code=="old")
  else assert(S.character~=oldChar and not next(S.character.actionBars.specs) and not next(S.character.heroChoices)
    and S.character.nativeMacros==nil and S.character.macroPool==nil and S.character.recovery==nil and S.character.raidDifficulty==5)end
  local db,char=S.db,S.character;S:Init();assert(S.db==db and S.character==char,"current roots are retained on repeated initialization")
 end
end
-- The first updated character creates new account builds. Another old
-- character logging in later resets only its own character root.
LycheeTalentDB,LycheeTalentCharacterDB=account("v1"),character("v1");S:Init()
local currentAccount=S.db;local saved=assert(S:Save("New V2 build","new-code","mythic","",71))
S.character.heroChoices["71"]=62
local firstCharacter=S.character
LycheeTalentCharacterDB=character("v1");S:Init()
assert(S.db==currentAccount and #S.builds==1 and S.builds[1]==saved and not next(S.character.actionBars.specs))
LycheeTalentCharacterDB=firstCharacter;S:Init()
assert(S.db==currentAccount and S.character==firstCharacter and S.character.heroChoices["71"]==62 and S.builds[1]==saved)
-- Non-table and future-schema roots also start fresh, independently.
LycheeTalentDB="invalid";LycheeTalentCharacterDB=firstCharacter;S:Init()
assert(#S.builds==0 and S.character==firstCharacter)
local current=S.db
LycheeTalentCharacterDB={schema="Lychee.Talent.Schema.Future:",recovery={code="future"}};S:Init()
assert(S.db==current and S.character.schema==schema and S.character.recovery==nil)
print("PASS V2 initialization: independent account/character reset matrix, no migration/native writes, current data retained, later old character preserves new account builds")
