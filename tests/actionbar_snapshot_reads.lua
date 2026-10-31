-- One passive observation has one stable previous layout, not two full clones.
local T=assert(loadfile('tests/macro_runtime.lua'))()(true)
local A,B=T.A,T.B
T.native[1]={name='Shared',icon=1,body='/say shared'}
for i=1,180 do T.slots[i]=i<=60 and {kind='macro',id=1,plain=true}or {kind='spell',id=10000+i}end
local initial=assert(B:Capture(T.spec));assert(B:SeedDefault(T.spec,initial,'fixture'))
T.activate('shared',true,initial);B:Init()
local gets=0;local get=B.Get
B.Get=function(self,...)gets=gets+1;return get(self,...)end
T.slots[61]={kind='spell',id=500};T.emit('ACTIONBAR_SLOT_CHANGED',61);T.settle()
assert(gets==1,'passive capture clones the previous layout more than once: '..gets)
local state=B:Spec(T.spec)
assert(state.default.slots[61].id==500 and initial.slots[61].id==10061,'edit saved without mutating earlier snapshot')
local independent=assert(B:Capture(T.spec));assert(B:SaveIndependent(T.spec,'mine',independent))
T.activate('mine',false,independent);gets=0
T.slots[61]={kind='spell',id=600};T.emit('ACTIONBAR_SLOT_CHANGED',61);T.settle()
assert(gets==1 and state.profiles.mine.slots[61].id==600 and state.default.slots[61].id==500,'save keeps independent ownership')
print('PASS passive snapshot reads: one previous clone, live slot save, independent/shared isolation')
