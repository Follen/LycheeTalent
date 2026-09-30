local testSpec=tonumber(arg[1]) or 62
local A={L={TITLE='荔枝天赋'},Store={character={}},UI={},GetSpec=function()return testSpec end,Message=function(self,k)self.message=k end}
local char=A.Store.character
local nodes={[10]={ID=10,name='User config',type=1,usesSharedActionBars=false,code='personal'},[20]={ID=20,name='Lychee 62-1',type=1,usesSharedActionBars=false,code='old'}}
local selected,activeCode,staged=20,'old',nil
local slots={};for i=1,180 do slots[i]={} end;slots[1]={kind='spell',id=100,sub='spell'}
local cursor,frames,timers,callbacks=nil,{},{},{}
local commits,loads,creates,barReads=0,0,0,0
function InCombatLockdown()return false end
local now=0
function GetTime()return now end
function time()return 1 end
function GetCursorInfo()return cursor and cursor.kind end
function ClearCursor()cursor=nil end
function GetActionInfo(i)barReads=barReads+1;local s=slots[i];return s.kind,s.id,s.sub end
function PickupAction(i,keep)
 if A.Apply then assert(A.Apply.op,'plugin cursor calls must finish within Applying')end
 cursor=slots[i];if not keep then slots[i]={}end
end
function PlaceAction(i)local old=slots[i];slots[i]=cursor;cursor=old.kind and old or nil end
C_Spell={PickupSpell=function(id)cursor={kind='spell',id=id,sub='spell'}end}
function CreateFrame()
 local f={};frames[#frames+1]=f
 function f:RegisterEvent(e)self[e]=true end
 function f:UnregisterAllEvents()for k,v in pairs(self)do if v==true then self[k]=nil end end end
 function f:SetScript(_,fn)self.handler=fn end
 return f
end
C_Timer={NewTimer=function(delay,fn)local t={delay=delay,fn=fn,Cancel=function(self)self.cancelled=true end};timers[#timers+1]=t;return t end}
Enum={TraitConfigType={Combat=1},LoadConfigResult={Error=0,NoChangesNecessary=1,LoadInProgress=2,Ready=3}}
local function emit(e,id)for _,f in ipairs(frames)do if f[e]then f.handler(f,e,id)end end end
local function settle()
 for step=1,100 do
  local progress=false
  local pending=callbacks;callbacks={}
  for _,fn in ipairs(pending)do fn();progress=true end
  local old=timers;timers={}
  for _,t in ipairs(old)do if not t.cancelled then if t.delay<=1 then now=now+t.delay;t.fn();progress=true else timers[#timers+1]=t end end end
  if not progress then return end
 end
 error('unbounded transition')
end
C_Traits={GetConfigInfo=function(id)return nodes[id]end,ConfigHasStagedChanges=function()return staged~=nil end,RollbackConfig=function()staged=nil;return true end}
C_ClassTalents={
 DeleteConfig=function(id)assert(id~=selected);nodes[id]=nil end,
 GetActiveConfigID=function()return 1 end,GetLastSelectedSavedConfigID=function()return selected end,
 GetConfigIDsBySpecID=function()local r={};for id in pairs(nodes)do r[#r+1]=id end;return r end,
 CanEditTalents=function()return true end,CanChangeTalents=function()return true,true end,GetStarterBuildActive=function()return false end,
 CanCreateNewConfig=function()return false end,ImportLoadout=function()creates=creates+1;error('existing working config must be reused')end,
 RenameConfig=function(id,name)callbacks[#callbacks+1]=function()nodes[id].name=name;emit('TRAIT_CONFIG_UPDATED',id)end end,SetUsesSharedActionBars=function(id,shared)callbacks[#callbacks+1]=function()nodes[id].usesSharedActionBars=shared;emit("TRAIT_CONFIG_UPDATED",id)end end,
 UpdateLastSelectedSavedConfigID=function(_,id)selected=id end,IsConfigPopulated=function()return true end,
 LoadConfig=function(id,auto)
  assert(auto);loads=loads+1
  callbacks[#callbacks+1]=function()activeCode=nodes[id].code;if nodes[id].bar then slots[1]={kind='spell',id=nodes[id].bar,sub='spell'} end;staged=nil;emit('TRAIT_CONFIG_UPDATED',1)end
  return 2
 end,
 CommitConfig=function(id)
  commits=commits+1;local code=staged
  callbacks[#callbacks+1]=function()activeCode=code;nodes[id].code=code;staged=nil;emit('TRAIT_CONFIG_UPDATED',1)end
  return true
 end,
 SaveConfig=function(id)nodes[id].code=activeCode;return true end,
}
A.Talents={Code=function(_,b)return b.code end,Validate=function(_,code)return code,testSpec end,Entries=function(_,code)return {code=code}end,
 Frame=function()return {}end,ReadEntries=function(_,id)return {code=id==1 and (staged or activeCode) or nodes[id].code}end,
 Export=function(_,draft)return (draft and staged) or activeCode end,
 Matches=function(_,id,e)return (id==1 and (staged or activeCode) or nodes[id].code)==e.code end,
 StageEntries=function(_,id,e)assert(id==1);staged=e.code;return true end}
local builds={a={id='a',code='alpha'},b={id='b',code='beta'}}
A.Catalog={Find=function(_,id)return builds[id]end}
assert(loadfile('addon/LycheeTalent/ActionBars.lua'))('LycheeTalent',A)
local B=A.ActionBars
assert(B:SeedDefault(testSpec,B:Capture(testSpec),'first-use'))
local independent=assert(B:Capture(testSpec));independent.slots[1].id=200
assert(B:SaveIndependent(testSpec,'a',independent))
B:Spec(testSpec).working={id=20,name=nodes[20].name,spec=testSpec}
assert(loadfile('addon/LycheeTalent/Apply.lua'))('LycheeTalent',A)
local panelShown,painted=false,false
A.UI.frame={IsShown=function()return panelShown end}
A.UI.Refresh=function()if A.Apply.op then painted=true end end
panelShown=true
local readsBefore=barReads
assert(A.Apply:Start(builds.a,false));assert(A.Apply.op and A.Apply.op.stage=='capture-bars','Applying covers the initial capture')
assert(painted and barReads==readsBefore,'Applying paints before cursor work starts')
panelShown=false -- closing the panel must leave the independent transaction alive
settle()
assert(not A.Apply.op and A.message=='APPLY_SUCCESS',tostring(A.message))
assert(activeCode=='alpha' and nodes[20].code=='alpha' and nodes[20].name=='荔枝天赋','one localized working config')
assert(slots[1].id==200 and A.Apply:CurrentBuildID()=='a','independent layout restored')
assert(not A.Apply.nextStep and not A.Apply.timer,'successful hidden-panel apply leaves no operation timers')
slots[1].id=201
assert(A.Apply:Start(builds.b,true));settle()
assert(not A.Apply.op and A.message=='APPLY_SUCCESS')
assert(slots[1].id==100,'switching back to default restores original default')
assert(B:Get(testSpec,'a',false).slots[1].id==201,'leaving independent saves user edits')
assert(A.Apply:Start(builds.a,false));settle()
assert(slots[1].id==201,'independent edits survive roundtrip')
assert(B:Get(testSpec,nil,true).slots[1].id==100,'default was never overwritten by independent layout')
assert(creates==0 and commits==3 and loads==0,'repeat builds reuse same saved config without extra native load')
assert(nodes[10].code=='personal' and nodes[10].name=='User config','user native config preserved')
A.L.TITLE='Lychee Talent'
assert(A.Apply:Start(builds.b,true));settle()
assert(nodes[20].name=='Lychee Talent','locale change updates exact owned config')
print('PASS single config: event completion, localized reuse, independent/default roundtrip, native user config preservation')

-- WCL can encode a free hero rank as purchased. The active tree matches the
-- effective rank, while the saved config omits the server-derived grant.
local baseEntries,baseMatches=A.Talents.Entries,A.Talents.Matches
A.Talents.Entries=function(_,code)return {code=code,requested=true}end
A.Talents.Matches=function(self,id,entries)
 if id~=1 and entries.requested then return false,{kind='missing-derived-grant'} end
 return baseMatches(self,id,entries)
end
assert(A.Apply:Start(builds.a,false));settle()
assert(not A.Apply.op and A.message=='APPLY_SUCCESS','server-derived hero grant must not cause a false timeout')
A.Talents.Entries=baseEntries;A.Talents.Matches=baseMatches
print('PASS native canonicalization: effective active talents and canonical saved config both verified')

-- Fresh install: one creation, then reuse, even while starting on a user config.
char={};A.Store.character=char
nodes={[10]={ID=10,name='User config',type=1,usesSharedActionBars=false,code='personal'}}
selected=10;activeCode='personal';slots[1]={kind='spell',id=900,sub='spell'}
C_ClassTalents.CanCreateNewConfig=function()return true end
C_ClassTalents.ImportLoadout=function(_,entries,name)
 creates=creates+1;nodes[50]={ID=50,name=name,type=1,usesSharedActionBars=true,code=entries.code}
 callbacks[#callbacks+1]=function()emit('TRAIT_CONFIG_CREATED',nodes[50])end
 return true
end
assert(not B:Get(testSpec,nil,true),'first use waits for Applying before capturing the native layout')
assert(A.Apply:Start(builds.a,false));settle()
assert(B:Get(testSpec,nil,true).slots[1].id==900,'first application captures the current native default')
assert(not A.Apply.op and A.message=='APPLY_SUCCESS',tostring(A.message))
assert(creates==1 and B:Working(testSpec).id==50 and not nodes[50].usesSharedActionBars,'create one isolated localized config')
assert(A.Apply:Start(builds.b,true));settle()
assert(creates==1 and nodes[10].code=='personal' and slots[1].id==900,'subsequent default build reuses config and original default')
staged='manual draft'
local ok,reason,ticket=A.Apply:Start(builds.a,false)
assert(not ok and reason=='PENDING' and ticket and staged=='manual draft','manual draft never silently discarded')
staged='changed draft'
local accepted,why=A.Apply:ConfirmPending(ticket)
assert(not accepted and why=='PENDING_CHANGED' and staged=='changed draft','changed draft invalidates consent')
staged=nil
print('PASS first install and pending edits: one creation, later reuse, initial default captured, manual drafts preserved')

local nativeCommit=C_ClassTalents.CommitConfig
C_ClassTalents.CommitConfig=function()return false end
assert(A.Apply:Start(builds.a,false));settle()
assert(not A.Apply.op and A.message=='COMMIT_FAILED' and staged==nil,'rejected submission rolls back staging and ends operation')
C_ClassTalents.CommitConfig=function()
 callbacks[#callbacks+1]=function()staged=nil;emit('CONFIG_COMMIT_FAILED',1)end
 return true
end
assert(A.Apply:Start(builds.a,false));settle()
assert(not A.Apply.op and A.message=='COMMIT_FAILED','native failure event never claims success')
C_ClassTalents.CommitConfig=nativeCommit
assert(A.Apply:Start(builds.a,false))
local beforeInterrupt=commits
InCombatLockdown=function()return true end
emit('PLAYER_REGEN_DISABLED');settle()
assert(not A.Apply.op and commits==beforeInterrupt and A.message=='APPLY_COMBAT','combat prevents deferred mutation')
InCombatLockdown=function()return false end
assert(A.Apply:Start(builds.a,false))
A.Apply.timer.fn();settle()
assert(not A.Apply.op and A.message=='APPLY_TIMEOUT' and commits==beforeInterrupt,'timeout prevents deferred mutation')
assert(A.Apply:Start(builds.a,false));settle()
assert(A.message=='APPLY_SUCCESS' and creates==1,'recovery reuses the same config after failures')
print('PASS failures: rejected/event-failed commits, combat, timeout, safe retry without another config')

-- Shared bars save both on normal slot changes and before switching away.
B:Init()
assert(A.Apply:Start(builds.b,true));settle()
local independentBefore=B:Get(testSpec,'a',false).slots[1].id
slots[1].id=901;emit('ACTIONBAR_SLOT_CHANGED',1);settle()
assert(B:Get(testSpec,nil,true).slots[1].id==901,'shared edits autosave through the real event handler')
slots[1].id=902
assert(A.Apply:Start(builds.a,false));settle()
assert(B:Get(testSpec,nil,true).slots[1].id==902,'leaving shared saves edits before a deferred event can run')
assert(B:Get(testSpec,'a',false).slots[1].id==independentBefore,'shared save does not overwrite independent layout')

print('PASS shared autosave and pre-switch save preserve independent layouts')

-- The reported empty cursor macros must not stop the actual Apply pipeline.
A.L.BARS_PARTIAL='Preserved macro slots: %s'
local copiedPickup=PickupAction
for _,i in ipairs({77,78,113,114})do slots[i]={kind='macro',id=999,unreadable=true}end
PickupAction=function(i,keep)
 assert(A.Apply.op,'all addon cursor work belongs to Applying')
 if slots[i].unreadable then assert(keep==true,'unreadable macro must stay in place');return end
 return copiedPickup(i,keep)
end
assert(A.Apply:Start(builds.b,true));settle()
assert(activeCode=='beta' and not A.Apply.op and char.lastAttempt.reason=='APPLY_SUCCESS','talent switch completes')
assert(A.message=='Preserved macro slots: 77, 78, 113, 114','partial action restore is visible, not silent success')
assert(char.recovery.actionBars.reason=='BARS_PARTIAL','partial restore is retained in diagnostics')
for _,i in ipairs({77,78,113,114})do assert(slots[i].unreadable)end
assert(slots[1].id==902,'readable actions still restore')
-- A different failure remains blocking and now records the failing slot.
local previousRecovery=char.recovery
PickupAction=function(i,keep)
 if slots[i].unreadable then cursor={kind='spell',id=999};return end
 return copiedPickup(i,keep)
end
local started,why=A.Apply:Start(builds.a,false)
assert(started and A.Apply.op and A.Apply.op.stage=='capture-bars','initial capture runs within Applying')
assert(char.recovery==previousRecovery,'starting does not discard an earlier recovery backup')
settle()
assert(not A.Apply.op and char.lastAttempt.reason=='BARS_MACRO_READ')
assert(char.lastAttempt.stage=='capture-bars' and char.lastAttempt.slot==77)
assert(char.recovery==previousRecovery and not cursor,'failed capture keeps existing recovery data and clears temporary cursor')
PickupAction=copiedPickup
local previousLayout=B:Get(testSpec,'b',true).slots[1].id
assert(A.Apply:Start(builds.a,false))
cursor={kind='item',id=123} -- user picks something up before the deferred capture
settle()
assert(not A.Apply.op and char.lastAttempt.reason=='BARS_CURSOR' and cursor.id==123,
 'deferred capture must preserve a newly occupied player cursor')
assert(char.recovery==previousRecovery and B:Get(testSpec,'b',true).slots[1].id==previousLayout,
 'cursor interruption preserves the prior backup and layout')
print('PASS unreadable macro integration: talents switch, other actions restore, preserved slots reported, early failures recorded')
