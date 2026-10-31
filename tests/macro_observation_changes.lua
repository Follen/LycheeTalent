-- Native UPDATE_MACROS can be a notification without a content mutation.
-- Observe real changes, but do not clone/save a 180-slot layout for no change.
local T=assert(loadfile('tests/macro_runtime.lua'))()(true)
local A,B,M=T.A,T.B,T.A.Macros
for i=1,75 do T.native[i]={name='Observe'..i,icon=134400+i,body='/say original '..i}end
for slot=1,180 do
 if slot<=60 then T.slots[slot]={kind='macro',id=75,plain=true}
 elseif slot<=150 then T.slots[slot]={kind='spell',id=10000+slot}
 else T.slots[slot]={}end
end
local snapshot=assert(B:Capture(T.spec));assert(B:SeedDefault(T.spec,snapshot,'fixture'))
local state=B:Spec(T.spec);state.applied={id='observed',spec=T.spec,shared=true}
B:Init()
local ref=state.default.slots[1].id
local logical=state.default.macros[ref].nativeID
local originalNative=M.registry.records[logical].native
local saves,gets=0,0
local save,get=B.SaveLayout,B.Get
B.SaveLayout=function(self,...)saves=saves+1;return save(self,...)end
B.Get=function(self,...)gets=gets+1;return get(self,...)end
for i=1,100 do T.emit('UPDATE_MACROS');T.settle()end
assert(saves==0 and gets==0,'unchanged macro notices clone/save full layouts: '..saves..' saves, '..gets..' gets')
assert(M.registry.records[logical].native==originalNative,'unchanged native records churn')
-- A real body edit still propagates to the current saved layout.
EditMacro(75,nil,nil,'/say edited')
M:Current() -- another read can synchronize before the native notification
T.settle()
assert(saves==1 and state.default.macros[ref].body=='/say edited')
assert(state.default.macros[ref].nativeID==logical)
-- Native renumbering must update the same logical reference, not be skipped.
DeleteMacro(2);T.settle()
assert(M.registry.records[logical].index==74)
assert(state.default.macros[ref].nativeID==logical)
EditMacro(74,'Renamed',nil,nil);T.settle()
assert(state.default.macros[ref].name=='Renamed')
-- Deleting the referenced macro invalidates its ID and retains the backup.
DeleteMacro(74);T.settle()
assert(M.registry.records[logical].index==nil)
local pending=state.default.pendingMacros and state.default.pendingMacros[1]
assert(pending and pending.macro.nativeID==logical and pending.macro.body=='/say edited')
-- Post-change repeated notices are no-ops again.
saves,gets=0,0
for i=1,100 do T.emit('UPDATE_MACROS');T.settle()end
assert(saves==0 and gets==0)
assert(M.registry.nextID==75,'notifications must not grow macro registry')
assert(T.writes==2,'plugin must not create/edit/delete macros')
-- A delayed Apply can observe an edit before its layout may be saved.
-- Deleting that macro must retain both the last confirmed original text and
-- the previously persisted layout backup; dead records are not disposable.
do
 local R=assert(loadfile('tests/macro_runtime.lua'))()(true)
 local C,D,N=R.A,R.B,R.A.Macros
 R.native[1]={name='DeferredDelete',icon=1,body='/say original'}
 R.slots[1]={kind='macro',id=1,plain=true}
 local saved=assert(D:Capture(R.spec));assert(D:SeedDefault(R.spec,saved,'fixture'));R.activate('owner',true,saved);D:Init()
 local key=saved.slots[1].id;local id=saved.macros[key].nativeID
 C.Apply.op={stage='applying'}
 EditMacro(1,nil,nil,'/say edited-before-delete');R.settle()
 DeleteMacro(1);R.settle()
 local retired=N.registry.records[id]
 assert(retired and not retired.index and retired.native.body=='/say edited-before-delete')
 assert(D:Get(R.spec,nil,true).macros[key].body=='/say original')
 C.Apply.op=nil;R.emit('PLAYER_REGEN_ENABLED');R.settle()
 local missing=D:Get(R.spec,nil,true).pendingMacros[1]
 assert(missing and missing.macro.nativeID==id and missing.macro.body=='/say original')
 assert(N.registry.records[id].native.body=='/say edited-before-delete','latest confirmed text must not be pruned')
end
print('PASS macro observation changes: no-op notices avoid layout/record copies; body/name edits and native renumbering remain live')
