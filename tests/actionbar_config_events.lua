-- Config events have a configID, unlike node notifications.
local T=assert(loadfile('tests/macro_runtime.lua'))()(true)
local A,B=T.A,T.B
C_ClassTalents={GetActiveConfigID=function()return 1 end}
for slot=1,180 do T.slots[slot]={kind='spell',id=10000+slot}end
assert(B:SeedDefault(T.spec,assert(B:Capture(T.spec)),'fixture'))
local state=B:Spec(T.spec);state.applied={id='owner',shared=true,config=20}
state.working={id=20,name='owned',spec=T.spec}
local invalidations,saves=0,0
A.Apply.InvalidateCurrent=function()invalidations=invalidations+1 end
local save=B.SaveLayout;B.SaveLayout=function(self,...)saves=saves+1;return save(self,...)end
B:Init()
for i=1,100 do T.emit('TRAIT_CONFIG_UPDATED',10);T.settle()end
assert(invalidations==0 and saves==0,'unrelated configs invalidate current state and clone layout: '..invalidations..'/'..saves)
T.emit('TRAIT_CONFIG_UPDATED',1);T.settle();assert(invalidations==1 and saves==0)
T.emit('TRAIT_CONFIG_UPDATED',20);T.settle();assert(invalidations==2 and saves==0)
-- A selected user loadout is active context even when it is not plugin-owned.
C_ClassTalents.GetLastSelectedSavedConfigID=function()return 60 end
assert(B:RelevantConfig(60))
-- Keep pending/recovery/creating identities observable before they are working.
A.Store.character.recovery={spec=T.spec,status='partial',targetConfig=30}
assert(B:RelevantConfig(30))
A.Apply.op={spec=T.spec,target=40,loading=41}
assert(B:RelevantConfig(40)and B:RelevantConfig(41));assert(not B:RelevantConfig(42))
A.Apply.op=nil
state.pendingBars={};state.applied.config=50
assert(B:RelevantConfig(50));state.pendingBars=nil
A.Store.character.recovery.status='complete';assert(not B:RelevantConfig(30))
-- Unknown/missing IDs cannot be classified; normal lifecycle still observes.
assert(B:RelevantConfig(nil));C_ClassTalents.GetActiveConfigID=function()end;assert(B:RelevantConfig(10))
print('PASS actionbar config events: unrelated config ignored; active/working/pending/creating and unknown identities stay observable')
