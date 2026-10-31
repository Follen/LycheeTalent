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
local frames={}
CreateFrame=function()
 local f={events={},scripts={}};frames[#frames+1]=f
 function f:RegisterEvent(name)self.events[name]=true end
 function f:UnregisterAllEvents()self.events={}end
 function f:SetScript(name,fn)self.scripts[name]=fn end
 return f
end
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
local spec,activeID,combat,starter=62,1,false,false
local A={GetSpec=function()return spec end,Store={character={}},UI={},Message=function(self,k)self.message=k end}

InCombatLockdown=function()return combat end
C_ClassTalents.GetActiveConfigID=function()return activeID end
C_ClassTalents.GetStarterBuildActive=function()return starter end
C_Traits.GetNodeInfo=function(config,id)return (config==activeID and activeNodes or savedNodes)[tostring(id)]end
GetMacroInfo=function()end
assert(loadfile('addon/LycheeTalent/Talents.lua'))('LycheeTalent',A)
assert(loadfile('addon/LycheeTalent/Macros.lua'))('LycheeTalent',A)
assert(loadfile('addon/LycheeTalent/ActionBars.lua'))('LycheeTalent',A)
assert(loadfile('addon/LycheeTalent/Apply.lua'))('LycheeTalent',A)
local X,B=A.Apply,A.ActionBars
activeNodes=state(replay.entries);savedNodes=activeNodes;selected=2;staging=false
local expected=A.Talents:Entries(replay.target)
local build={id='current-build',code=replay.target,source='user'}
local found=true
A.Catalog={Find=function(_,id)if found and id==build.id then return build end end}
local specState=B:Spec(spec)
specState.working={id=2,name=configs[2].name,spec=spec}
specState.applied={id=build.id,code=build.code,spec=spec,config=2,entries=expected,shared=true}
assert(A.Talents:Matches(activeID,expected),'real pinned Mage fixture must match before measuring')
local reads=0;local read=A.Talents.ReadEntries
A.Talents.ReadEntries=function(self,...)reads=reads+1;return read(self,...)end
B:Init()
local started=os.clock();collectgarbage('collect');local heap=collectgarbage('count')
for i=1,100 do assert(X:CurrentBuildID()==build.id);assert(B:Owner()==spec)end
print(string.format('CURRENT_STATE 100 UI+owner reads=%d elapsedMs=%.2f garbageKiB=%.1f',reads,(os.clock()-started)*1000,collectgarbage('count')-heap))
assert(reads==1,'repeated CurrentBuildID/Owner rebuilt the full native talent tree '..reads..' times')
local function current()assert(X:CurrentBuildID()==build.id)end
local function event(name,...)
 assert(B.events.events[name],'missing native event subscription '..name)
 B.events.scripts.OnEvent(B.events,name,...)
end
local function invalidates(name,...)
 current();local before=reads;event(name,...);B.pendingSpec=nil;B.resumeFailed=nil;current()
 assert(reads==before+1,name..' must invalidate the current-tree result')
end
for _,name in ipairs({'PLAYER_TALENT_UPDATE','TRAIT_CONFIG_UPDATED','TRAIT_CONFIG_LIST_UPDATED','TRAIT_CONFIG_CREATED','CONFIG_COMMIT_FAILED','PLAYER_REGEN_ENABLED',
 'SELECTED_LOADOUT_CHANGED','ACTIVE_COMBAT_CONFIG_CHANGED','ACTIVE_PLAYER_SPECIALIZATION_CHANGED'})do
 invalidates(name,2);B.pendingSpec=nil;B.resumeFailed=nil
end
-- Native notifications still invalidate while observers are gated by a write/op.
current();local before=reads;B.writing=true;event('TRAIT_CONFIG_UPDATED',2);B.writing=nil;current();assert(reads==before+1)
current();before=reads;X.op={};event('PLAYER_TALENT_UPDATE');X.op=nil;current();assert(reads==before+1)
-- Drafts are checked every call, without requiring an event to arrive first.
current();before=reads;staging=true;assert(not X:CurrentBuildID() and reads==before)
staging=false;current();assert(reads==before+1,'cancelled draft must revalidate')
-- Fast identity guards cannot become cached claims.
local function immediate(change,restore,label)
 current();local n=reads;change();assert(not X:CurrentBuildID() and reads==n,label)
 restore();current();assert(reads==n+1,label..' restoration requires fresh content')
end
local originalName=configs[2].name
immediate(function()configs[2].name='Renamed' end,function()configs[2].name=originalName end,'native rename')
local info=configs[2]
immediate(function()configs[2]=nil end,function()configs[2]=info end,'native deletion')
immediate(function()configs[2].type=99 end,function()configs[2].type=1 end,'native config type')
immediate(function()configs[2].usesSharedActionBars=true end,function()configs[2].usesSharedActionBars=false end,'native bar mode')
immediate(function()selected=3 end,function()selected=2 end,'selected native config')
immediate(function()starter=true end,function()starter=false end,'starter state')
immediate(function()combat=true end,function()combat=false end,'combat availability')
immediate(function()build.code='edited' end,function()build.code=replay.target end,'build edit')
immediate(function()found=false end,function()found=true end,'build deletion')
current();before=reads;activeID=4;current();assert(reads==before+1,'active config identity is part of key')
activeID=1;current();assert(reads==before+2)
-- Spec/world lifecycle is real event dispatch, not a direct cache helper call.
current();before=reads;spec=63;event('ACTIVE_PLAYER_SPECIALIZATION_CHANGED');assert(not X:CurrentBuildID())
spec=62;event('ACTIVE_PLAYER_SPECIALIZATION_CHANGED');B.pendingSpec=nil;B.resumeFailed=nil;current();assert(reads==before+1)
event('PLAYER_LEAVING_WORLD');before=reads;assert(not X:CurrentBuildID(true) and reads==before)
event('PLAYER_ENTERING_WORLD');assert(X:CurrentBuildID(true)==build.id and reads==before+1);B.pendingSpec=nil
event('PLAYER_LOGOUT');before=reads;assert(not X:CurrentBuildID(true) and reads==before)
event('PLAYER_ENTERING_WORLD');B.pendingSpec=nil;current()
-- UI node notifications are explicit invalidation, not another permanent listener.
assert(not B.events.events.TRAIT_NODE_CHANGED)
current();before=reads;X:InvalidateCurrent('TRAIT_NODE_CHANGED');current();assert(reads==before+1)
-- Partial bar state gates ownership every time but may still show verified talents.
specState.pendingBars={};specState.applied.partial=true
assert(not X:CurrentBuildID() and not B:Owner() and X:CurrentBuildID(true)==build.id)
specState.pendingBars=nil;B.pendingSpec=spec
assert(not X:CurrentBuildID() and X:CurrentBuildID(true)==build.id)
B.pendingSpec=nil;current()
-- Missing UI/native data is retried instead of being cached as a permanent no-match.
current();local frame=PlayerSpellsFrame.TalentsFrame
PlayerSpellsFrame.TalentsFrame=nil;assert(not X:CurrentBuildID())
PlayerSpellsFrame.TalentsFrame=frame;current()
-- Confirmed mismatches are cached too, then native talent updates revalidate.
local selectedNode=activeNodes['99830'];local previousEntry=selectedNode.activeEntry
selectedNode.activeEntry={entryID=123344};event('PLAYER_TALENT_UPDATE')
before=reads
for i=1,100 do assert(not X:CurrentBuildID())end
assert(reads==before+1,'a real mismatch must not rebuild the tree every refresh')
selectedNode.activeEntry=previousEntry;event('PLAYER_TALENT_UPDATE');current()
-- A replaced expected snapshot cannot reuse an old content result.
local previous=specState.applied.entries;local equivalent={}
for i,e in ipairs(previous)do equivalent[i]=copy(e)end
before=reads;specState.applied.entries=equivalent;current();assert(reads==before+1)
specState.applied.entries=previous;current()
-- Transaction validation itself is never memoized.
before=reads;assert(A.Talents:Matches(activeID,expected));assert(A.Talents:Matches(activeID,expected));assert(reads==before+2)
-- Native content tokens can confirm that a related notification changed no
-- ranks. Identity/draft guards and changes to expected values remain immediate.
local content='settled-a'
A.Talents.StableConfigToken=function()return content end
X:InvalidateCurrent();current();before=reads
for i=1,100 do event('TRAIT_CONFIG_UPDATED',2);current()end
assert(reads==before,'same native content token rereads every related notification: '..(reads-before))
local originalRanks=expected[1].ranksPurchased
expected[1].ranksPurchased=(originalRanks or 0)+1
assert(not X:CurrentBuildID() and reads==before+1,'in-place expected mutation reused an old match')
expected[1].ranksPurchased=originalRanks;current()
before=reads;content='settled-b';event('PLAYER_TALENT_UPDATE');current()
assert(reads==before+1,'changed native token must take a fresh full comparison')
before=reads;X:InvalidateCurrent('UI_SHOWN');current()
assert(reads==before+1,'reopening the window must refresh hidden node changes')
A.Talents.StableConfigToken=function()return nil end
before=reads;event('TRAIT_CONFIG_UPDATED',2);current();event('TRAIT_CONFIG_UPDATED',2);current()
assert(reads==before+2,'unavailable native token must retain the original live behavior')
specState.applied.entries=false
assert(not X:CurrentBuildID(),'malformed persisted entries must not be treated as a current build')
specState.applied.entries=expected;current()
print('PASS bounded current state: native tree read reused; event invalidation, immediate drafts/identity, world/spec, partial ownership and live transaction validation')
