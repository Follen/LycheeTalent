-- Native talent/config metadata is not evidence that an action slot changed.
local T=assert(loadfile('tests/macro_runtime.lua'))()(true)
local A,B,M=T.A,T.B,T.A.Macros
C_ClassTalents={GetActiveConfigID=function()return 1 end}
T.native[1]={name='Shared',icon=1,body='/say old'}
for i=1,180 do T.slots[i]=i<=60 and {kind='macro',id=1,plain=true}or {kind='spell',id=10000+i}end
local initial=assert(B:Capture(T.spec));assert(B:SeedDefault(T.spec,initial,'fixture'))
T.activate('owner',true,initial);B:Init();B.observedSpec=T.spec
local captures,saves,invalidations=0,0,0
local capture,save=B.Capture,B.SaveLayout
B.Capture=function(self,...)captures=captures+1;return capture(self,...)end
B.SaveLayout=function(self,...)saves=saves+1;return save(self,...)end
A.Apply.InvalidateCurrent=function()invalidations=invalidations+1 end
for i=1,100 do
 for _,event in ipairs({'TRAIT_CONFIG_UPDATED','PLAYER_TALENT_UPDATE','TRAIT_CONFIG_LIST_UPDATED','TRAIT_CONFIG_CREATED','SELECTED_LOADOUT_CHANGED','ACTIVE_COMBAT_CONFIG_CHANGED'})do T.emit(event,1);T.settle()end
end
assert(captures==0 and saves==0,'metadata notices capture/save 180 slots: '..captures..'/'..saves)
assert(invalidations==600,'talent state must still invalidate')
-- Real slot changes blocked by combat/reading/writing/Apply remain dirty.
local function editBlocked(kind,value)
 local before=captures
 if kind=='combat'then T.combat=true else B[kind]=true end
 T.slots[61]={kind='spell',id=value};T.emit('ACTIONBAR_SLOT_CHANGED',61);T.settle()
 assert(captures==before and B.slotDirty,'blocked slot edit was lost or captured early')
 if kind=='combat'then T.combat=false else B[kind]=nil end
 T.emit('PLAYER_REGEN_ENABLED');T.settle()
 assert(captures==before+1 and not B.slotDirty and B:Get(T.spec,nil,true).slots[61].id==value)
end
editBlocked('combat',501);editBlocked('reading',502);editBlocked('writing',503)
A.Apply.op={};local before=captures
T.slots[61]={kind='spell',id=504};T.emit('ACTIONBAR_SLOT_CHANGED',61);T.settle()
assert(captures==before and B.slotDirty);A.Apply.op=nil
T.emit('PLAYER_REGEN_ENABLED');T.settle();assert(not B.slotDirty and B:Get(T.spec,nil,true).slots[61].id==504)
-- A completed explicit restore/save consumes its own generated slot notices.
local target=assert(B:Get(T.spec,nil,true));target.slots[61].id=505
T.activate('owner',true,target);local after=captures
T.emit('TRAIT_CONFIG_UPDATED',1);T.settle();assert(captures==after and not B.slotDirty)
-- Macro edits can be synchronized elsewhere while combat prevents layout save.
T.combat=true;EditMacro(1,nil,nil,'/say latest');T.settle();M:Current()
local bodyBefore=T.body(B:Get(T.spec,nil,true),1);before=captures
assert(bodyBefore~='/say latest')
T.combat=false;T.emit('PLAYER_REGEN_ENABLED');T.settle()
assert(captures==before and T.body(B:Get(T.spec,nil,true),1)=='/say latest','pending macro revision must save without physical capture')
-- A failed passive save keeps its real edit dirty for a later safe boundary.
local realSave=B.SaveLayout;local reject=true
B.SaveLayout=function(self,...)if reject then reject=false;return nil,'SCHEMA' end;return realSave(self,...)end
T.slots[61]={kind='spell',id=508};T.emit('ACTIONBAR_SLOT_CHANGED',61);T.settle()
assert(B.slotDirty and B:Get(T.spec,nil,true).slots[61].id~=508)
T.emit('PLAYER_REGEN_ENABLED');T.settle();assert(not B.slotDirty and B:Get(T.spec,nil,true).slots[61].id==508)
B.SaveLayout=realSave
-- Unconsumed macro content also survives a read/write gate and an earlier scan.
for _,gate in ipairs({'reading','writing'})do
 B[gate]=true;EditMacro(1,nil,nil,'/say '..gate);T.settle();M:Current();B[gate]=nil
 before=captures;T.emit('PLAYER_REGEN_ENABLED');T.settle()
 assert(captures==before and T.body(B:Get(T.spec,nil,true),1)=='/say '..gate)
end
-- World exit cancels queued reads; reentry retains real unsaved edits.
T.slots[61]={kind='spell',id=506};T.emit('ACTIONBAR_SLOT_CHANGED',61)
assert(B.queued);T.emit('PLAYER_LEAVING_WORLD');assert(not B.queued)
T.emit('PLAYER_ENTERING_WORLD');T.settle();assert(B:Get(T.spec,nil,true).slots[61].id==506 and not B.slotDirty)
-- Exit saving is explicit even if no slot notification preceded it.
T.slots[61]={kind='spell',id=507};T.emit('ACTIONBAR_SLOT_CHANGED',61);assert(B.queued);T.emit('PLAYER_LOGOUT');assert(not B.queued);assert(B:Get(T.spec,nil,true).slots[61].id==507)

-- Resume must keep its manual-retry gate if the final persistent save fails.
B.pendingSpec=T.spec;B.resumeFailed=nil
B.SaveLayout=function()return nil,'SCHEMA'end
B:ResumeSpec()
assert(B.pendingSpec==T.spec and B.resumeFailed,'failed resume save must not release ownership pause')
B.SaveLayout=realSave

print('PASS observation routes: metadata only invalidates; deferred real slots/macros, explicit saves, resume failure, world cleanup and logout preserve ownership')
