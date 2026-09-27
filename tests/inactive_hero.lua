-- Production double-click service + pinned Blizzard serializer, replaying the
-- user's real Ready staging and the same-build DB2 node/entry definitions.
bit=require('bit');getn=table.getn
function tInvert(t)local r={};for k,v in pairs(t)do r[v]=k end;return r end
function CreateFromMixins(...)local r={};for i=1,select('#',...)do for k,v in pairs(select(i,...))do r[k]=v end end;return r end
function CreateAndInitFromMixin(m,...)local r=CreateFromMixins(m);r:Init(...);return r end
function Mixin(t,...)for i=1,select('#',...)do for k,v in pairs(select(i,...))do t[k]=v end end;return t end
StaticPopupDialogs={};ERROR_COLOR={WrapTextInColorCode=function(_,x)return x end}
dofile('analyze/Blizzard/ExportUtil.lua');dofile('analyze/Blizzard/Import.lua')
local data=dofile('tests/fixtures/mage-tree-69933.lua')
local replay=dofile('tests/fixtures/mage-staging-69933.lua')
Enum={TraitNodeType={Single=0,Tiered=1,Selection=2,SubTreeSelection=3},TraitConfigType={Combat=1},LoadConfigResult={Error=0,NoChangesNecessary=1,LoadInProgress=2,Ready=3}}
InCombatLockdown=function()return false end;time=function()return 1 end
CreateFrame=function()return {RegisterEvent=function()end,UnregisterAllEvents=function()end,SetScript=function()end}end
C_Timer={NewTimer=function()return {Cancel=function()end}end}
local configs={[2]={ID=2,name='Lychee 62-3',type=1,usesSharedActionBars=false},[3]={ID=3,name='Original',type=1,usesSharedActionBars=false}}
local activeNodes,savedNodes,staging
local function copy(t)local o={};for k,v in pairs(t)do o[k]=v end;return o end
local function state(entries)
 local out={}
 for id,n in pairs(data.nodes)do
  local r=copy(n);r.ranksPurchased=0;r.activeRank=0;r.activeEntry={entryID=n.entryIDs[1]};out[id]=r
 end
 for _,e in ipairs(entries)do
  local n=out[tostring(e.nodeID)]
  n.ranksPurchased=n.ranksPurchased+e.ranksPurchased;n.activeRank=n.activeRank+e.ranksPurchased+e.ranksGranted
  n.activeEntry={entryID=e.selectionEntryID}
 end
 return out
end
local f=CreateFromMixins(ClassTalentImportExportMixin)
PlayerSpellsFrame={TalentsFrame=f}
local s=ExportUtil.MakeImportDataStream(replay.original);local _,_,_,hash=f:ReadLoadoutHeader(s)
activeNodes=state({});savedNodes=activeNodes
C_Traits={
 GetTreeHash=function()return hash end,GetLoadoutSerializationVersion=function()return 2 end,
 GetTreeNodes=function()return data.order end,
 GetNodeInfo=function(config,id)return (config==1 and activeNodes or savedNodes)[tostring(id)]end,
 GetEntryInfo=function(_,id)local e=data.entries[tostring(id)];return {maxRanks=e.MaxRanks,subTreeID=e.TraitSubTreeID~=0 and e.TraitSubTreeID or nil}end,
 GetConfigInfo=function(id)return configs[id]end,ConfigHasStagedChanges=function(id)return id==1 and staging end,
 RollbackConfig=function()activeNodes=savedNodes;staging=false;return true end,
}
local selected,commits,loads=3,0,0
C_ClassTalents={
 GetActiveConfigID=function()return 1 end,GetTraitTreeForSpec=function()return 658 end,
 GetConfigIDsBySpecID=function()return {2,3}end,GetLastSelectedSavedConfigID=function()return selected end,
 GetStarterBuildActive=function()return false end,CanEditTalents=function()return true end,CanCreateNewConfig=function()return true end,
 IsConfigPopulated=function()return true end,ImportLoadout=function()error('reuse the existing owned loadout')end,
 SetUsesSharedActionBars=function()error('mode already matches')end,UpdateLastSelectedSavedConfigID=function(_,id)selected=id end,
 LoadConfig=function(id,auto)assert(id==2 and auto==true);loads=loads+1;activeNodes=state(replay.entries);staging=true;return 3 end,
 CommitConfig=function(id)assert(id==2);commits=commits+1;staging=false;return true end,
}
local A={GetSpec=function()return 62 end,Store={character={bindings={['captured:independent']={id=2,name='Lychee 62-3',spec=62,code=replay.target,shared=false}}}},UI={},Message=function(self,k)self.message=k end}
assert(loadfile('addon/LycheeTalent/Talents.lua'))('LycheeTalent',A)
activeNodes=state(A.Talents:Entries(replay.original));savedNodes=activeNodes
assert(A.Talents:Export()==replay.original,'same-build DB2 fixture reproduces original native export exactly')
activeNodes=state(replay.entries)
assert(A.Talents:Matches(1,A.Talents:Entries(replay.target)),'inactive hero grant is normalized')
local expected=A.Talents:Entries(replay.target)
-- Only inactive automatic grants may differ. Effective ranks/choices remain exact.
local n=activeNodes['62085'];n.ranksPurchased=0;n.activeRank=0
assert(not A.Talents:Matches(1,expected),'missing purchased class rank still rejected')
activeNodes=state(replay.entries)
local hero=activeNodes['94647'];hero.ranksPurchased=0;hero.activeRank=0
assert(not A.Talents:Matches(1,expected),'missing granted rank in selected hero tree still rejected')
activeNodes=state(replay.entries)
activeNodes['99830'].activeEntry={entryID=123344}
assert(not A.Talents:Matches(1,expected),'wrong hero specialization still rejected')
print('PASS real Mage staging: inactive hero grant ignored; effective ranks/hero selection/original checked')

