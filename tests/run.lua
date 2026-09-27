local root=arg[1] or "addon/LycheeTalent/"
local count=0
local function check(v,msg) count=count+1; assert(v,msg or ("check "..count)) end
local function load(name,A) assert(loadfile(root..name))("LycheeTalent",A) end
time=function() return 1790400000 end; date=os.date; GetLocale=function() return "enUS" end
local A={}; load("Locales.lua",A); load("Storage.lua",A)
A.Store:Init()
local s=A.Store
local first=s:Save("Alpha","encoded","mythic","Dungeon",71)
local second=s:Save("Beta","encoded","raid","Boss",71)
check(first.id~=second.id,"unique IDs")
local out={}; s:Query(71,"mythic","all","",out); check(#out==1 and out[1]==first,"scene filter")
s:Query(71,"mythic","all","boss",out); check(#out==1 and out[1]==second,"search crosses scenarios")
s:Query(72,"mine","all","",out); check(#out==0,"specialization isolation")
check(s:Delete(first.id)); check(s:Undo()); check(s:Find(first.id)==first,"undo retains identity")
first.favorite=true; s:Query(71,"mine","all","",out); check(out[1]==second,"legacy favorites no longer affect ordering")
s:Update(first.id,"Renamed","other","raid","New boss",71); check(first.name=="Renamed" and first.scene=="raid","edit persists")
local b,e=s:Save("   ","encoded","raid","",71); check(not b and e=="BAD_NAME")
LycheeTalentDB={version=99,builds={{id=3}}};s:Init(); check(s.readonly and #s.builds==0,"future schema preserved"); check(LycheeTalentDB.version==99)
LycheeTalentDB=nil;s:Init()

-- Strict talent stream tests use the pinned Blizzard serializer and parser, not a rewritten oracle.
bit=require("bit"); getn=table.getn
function tInvert(t) local r={};for k,v in pairs(t) do r[v]=k end;return r end
function CreateFromMixins(...) local r={};for i=1,select('#',...) do for k,v in pairs(select(i,...)) do r[k]=v end end;return r end
function CreateAndInitFromMixin(m,...)local r=CreateFromMixins(m);r:Init(...);return r end
function Mixin(t,...) for i=1,select('#',...) do for k,v in pairs(select(i,...)) do t[k]=v end end;return t end
StaticPopupDialogs={}; ERROR_COLOR={WrapTextInColorCode=function(_,x)return x end}
dofile("analyze/Blizzard/ExportUtil.lua"); dofile("analyze/Blizzard/Import.lua")
local combat=false; InCombatLockdown=function() return combat end
GetBuildInfo=function() return "12.1.0" end
A.GetSpec=function()return 71,"Arms" end
C_SpecializationInfo={GetSpecialization=function()return 1 end,GetSpecializationInfo=function()return 71,"Arms" end}
C_AddOns={LoadAddOn=function()return true end,DoesAddOnExist=function()return false end}
Enum={TraitNodeType={Selection=2,SubTreeSelection=3,Tiered=4},TraitConfigType={Combat=1},LoadConfigResult={Error=0,NoChangesNecessary=1,LoadInProgress=2,Ready=3}}
local nodes={
    [10]={ID=10,entryIDs={100},maxRanks=1,type=0,activeRank=1,ranksPurchased=0,activeEntry={entryID=100}},
    [20]={ID=20,entryIDs={200,201},maxRanks=1,type=2,activeRank=1,ranksPurchased=1,activeEntry={entryID=200}},
    [30]={ID=30,entryIDs={300},maxRanks=2,type=0,activeRank=2,ranksPurchased=2,activeEntry={entryID=300}},
    [40]={ID=40,entryIDs={400,401},maxRanks=3,type=4,activeRank=3,ranksPurchased=3,activeEntry={entryID=400}},
}
local hash={};for i=1,16 do hash[i]=1 end
C_Traits={GetTreeHash=function()return hash end,GetLoadoutSerializationVersion=function()return 2 end,GetTreeNodes=function()return {10,20,30,40} end,
    GetNodeInfo=function(_,id)return nodes[id] end,ConfigHasStagedChanges=function()return false end,
    GetEntryInfo=function(_,id)return {maxRanks=id==400 and 2 or 1} end}
C_ClassTalents={GetTraitTreeForSpec=function()return 1 end,GetActiveConfigID=function()return 1 end}
PlayerUtil={GetCurrentSpecID=function()return 71 end}
PlayerSpellsFrame={TalentsFrame=CreateFromMixins(ClassTalentImportExportMixin)}
load("Talents.lua",A)
local exported=A.Talents:Export();check(type(exported)=="string","export works with pinned serializer")
check(A.Talents:Validate(exported)==exported,"roundtrip validation")
local bad,why=A.Talents:Validate(exported:sub(1,-3));check(not bad and why=="BAD_CODE","truncation rejected")
check(A.Talents:Matches(1,A.Talents:Entries(exported)),"canonical entry comparison")
local built={id="fixture",version="1",source="builtin",specIndex=1,patch="12.1",nodes={{100,1},{200,1},{300,2},{400,2},{401,1}}}
check(A.Talents:Code(built)==exported,"WCL entry encoding handles granted, choice and tiered nodes")
built.version="2";built.nodes[2]={999999,1};check(not A.Talents:Code(built),"unknown entries refuse application")
local packed={id="packed-fixture",version="1",source="builtin",specIndex=1,patch="12.1",nodes="100:1;200:1;300:2;400:2;401:1;"}
check(A.Talents:Code(packed)==exported,"packed WCL entries preserve the native export")
packed.specIndex=2;local ignored,wrongSpec=A.Talents:Code(packed)
check(not ignored and wrongSpec=="WRONG_SPEC","cached built-in code rejects another specialization")
packed.specIndex=1;packed.nodes="100:1;bad";local malformed,reason=A.Talents:Code(packed)
check(not malformed and reason=="BAD_CODE","malformed packed entries are rejected before cache reuse")
combat=true;check(not A.Talents:Export(),"combat blocks export preparation");combat=false

print("PASS "..count.." checks: storage and pinned talent serialization")
