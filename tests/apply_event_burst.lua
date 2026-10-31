-- Native active data may settle before the saved configuration does.
-- Repeated notices in one frame must not serialize/compare the whole tree each time.
local spec,combat=62,false
local active,saved,drafted='old','old',false
local checks,restores,commits=0,0,0
local frames,timers={},{}
local state={default={},working={id=20,name='Lychee Talent',spec=62}}
local char={}
local A={L={TITLE='Lychee Talent'},Store={character=char},UI={},GetSpec=function()return spec end}
function A:Message(key)self.message=key end
function InCombatLockdown()return combat end
local now=1
function GetTime()return now end
function time()return 1 end
function GetCursorInfo()end
Enum={TraitConfigType={Combat=1},LoadConfigResult={Error=0,Ready=3}}
C_Timer={NewTimer=function(delay,fn)
 local t={delay=delay,fn=fn,Cancel=function(self)self.cancelled=true end};timers[#timers+1]=t;return t
end}
function CreateFrame()
 local f={};frames[#frames+1]=f
 function f:RegisterEvent(e)self[e]=true end
 function f:UnregisterAllEvents()for k,v in pairs(self)do if v==true then self[k]=nil end end end
 function f:SetScript(_,fn)self.handler=fn end
 return f
end
local function emit(event,value)for _,f in ipairs(frames)do if f[event]then f.handler(f,event,value)end end end
local function tick()
 local pending=timers;timers={}
 for _,t in ipairs(pending)do
  if not t.cancelled then if t.delay<=1 then now=now+t.delay;t.fn()else timers[#timers+1]=t end end
 end
end
local function settle()for i=1,8 do tick()end end
C_Traits={
 GetConfigInfo=function(id)return {ID=id,name=A.L.TITLE,type=1,usesSharedActionBars=false}end,
 ConfigHasStagedChanges=function()return drafted end,
 RollbackConfig=function()drafted=false;return true end,
}
C_ClassTalents={
 GetActiveConfigID=function()return 1 end,GetLastSelectedSavedConfigID=function()return 20 end,
 GetConfigIDsBySpecID=function()return {20}end,
 CanEditTalents=function()return true end,GetStarterBuildActive=function()return false end,
 UpdateLastSelectedSavedConfigID=function()end,
 CommitConfig=function()commits=commits+1;return true end,
 SaveConfig=function()saved=active;return true end,
}
A.Talents={
 Code=function(_,build)return build.code end,Validate=function(_,code)return code,spec end,
 Entries=function(_,code)return {code=code}end,Export=function()return active end,
 Frame=function()return {}end,
 ReadEntries=function(_,id)checks=checks+1;return {code=id==1 and active or saved}end,
 Matches=function(_,id,e)checks=checks+1;return (id==1 and active or saved)==e.code end,
 StageEntries=function(_,id,e)active=e.code;drafted=true;return true end,
}
A.ActionBars={
 Spec=function()return state end,Working=function()return state.working,C_Traits.GetConfigInfo(20)end,
 IsShared=function()return true end,Capture=function()return {}end,Get=function()return {}end,
 SaveLayout=function()return true end,
 Restore=function()restores=restores+1;return true end,
}
A.Macros={Copy=function(value)return value end}
assert(loadfile('addon/LycheeTalent/Apply.lua'))('LycheeTalent',A)
local X=A.Apply
local function start()
 state.applied=nil;state.active=nil;active='old';saved='old';drafted=false
 assert(X:Start({id='target',code='target'},true));settle()
 assert(X.op and X.op.stage=='applying' and commits>0)
end
start();drafted=false
local before=checks
for i=1,100 do emit('TRAIT_CONFIG_UPDATED',1)end
assert(checks==before,'native event burst repeatedly compares the whole tree before next frame: '..(checks-before))
tick()
assert(checks-before==3 and X.op and restores==0,'one fresh active/canonical/saved check, no premature success')
before=checks;saved=active
for i=1,100 do emit('TRAIT_CONFIG_UPDATED',20);emit('PLAYER_TALENT_UPDATE')end
assert(checks==before)
settle()
assert(not X.op and char.lastAttempt.reason=='APPLY_SUCCESS' and restores==1)
assert(not X.advanceStep and not X.nextStep and not X.timer,'completion releases every operation timer')
-- Terminal errors and context changes are immediate, even with a queued notice.
start();drafted=false;emit('TRAIT_CONFIG_UPDATED',1);before=checks
emit('CONFIG_COMMIT_FAILED',1)
assert(not X.op and char.lastAttempt.reason=='COMMIT_FAILED');settle();assert(checks==before)
start();drafted=false;emit('TRAIT_CONFIG_UPDATED',1);combat=true;emit('PLAYER_REGEN_DISABLED')
assert(not X.op and char.lastAttempt.reason=='APPLY_COMBAT');combat=false;settle()
start();drafted=false;emit('TRAIT_CONFIG_UPDATED',1);spec=63;emit('ACTIVE_PLAYER_SPECIALIZATION_CHANGED')
assert(not X.op and char.lastAttempt.reason=='APPLY_SPEC_CHANGED');spec=62;settle()
-- No recurring polling after a mismatching read; only later events retry.
start();drafted=false;emit('TRAIT_CONFIG_UPDATED',1);tick();before=checks
settle();assert(checks==before and X.op,'waiting native data must not start a polling loop')
X.timer.fn();settle();assert(not X.op and char.lastAttempt.reason=='APPLY_TIMEOUT' and not X.advanceStep)
-- Native loading has the same active/saved settling window and must not fan out.
X.op={spec=62,stage='native-loading',loading=20,afterLoad=function()end}
active='target';saved='old';drafted=false;before=checks
for i=1,100 do X:OnEvent('TRAIT_CONFIG_UPDATED',1)end
assert(checks==before);tick()
assert(checks-before==2 and X.op.stage=='native-loading')
saved=active;X:OnEvent('TRAIT_CONFIG_UPDATED',20);tick()
assert(X.op.stage=='native-loaded');X:Finish(false,'TEST_STOP');settle()
-- Async reconciliation exceptions use the same failure/recovery reporting.
start();drafted=false;local original=A.Talents.Matches
A.Talents.Matches=function()error('native data unavailable during reconcile')end
emit('TRAIT_CONFIG_UPDATED',1);tick();A.Talents.Matches=original
assert(not X.op and char.lastAttempt.reason=='APPLY_FAILED' and char.lastAttempt.luaError:find('native data unavailable',1,true))
assert(not X.advanceStep and not X.nextStep and not X.timer)
-- Created config identity must be captured synchronously before any timer.
X.op={spec=62,stage='creating',name=A.L.TITLE,before={}}
X:OnEvent('TRAIT_CONFIG_CREATED',{ID=77,name=A.L.TITLE,type=1})
assert(X.op.target==77 and X.op.targetName==A.L.TITLE)
X:Finish(false,'TEST_STOP');settle()
print('PASS apply event burst: one live check per frame, canonical saved verification, immediate failure/context/creation, timer cleanup')
