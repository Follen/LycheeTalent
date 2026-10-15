local T=assert(loadfile('tests/macro_runtime.lua'))()(arg[1]=='deferred')
local A,B=T.A,T.B
T.native[1]={name='same',icon=1,body='/cast Alpha'}
T.native[2]={name='same',icon=2,body='/cast Beta'}
T.slots[1]={kind='macro',id=1};T.slots[2]={kind='macro',id=2}
T.slots[3]={kind='spell',id=100,sub='spell'}
local initial=assert(B:Capture(62))
assert(B:SeedDefault(62,initial,'test'));assert(B:SaveIndependent(62,'other',initial))
B:Spec(62).applied={spec=62,id='shared',shared=true}
B:Init()
local copies=T.copies
T.cursor={kind='item',id=123}
EditMacro(1,nil,nil,'/cast Edited\n/say A');T.settle()
assert(T.body(B:Get(62,nil,true),1)=='/cast Edited\n/say A','macro event stores edited raw text immediately')
assert(T.body(B:Get(62,'other',false),1)=='/cast Alpha','inactive independent copy retains original')
assert(T.cursor.id==123 and T.copies==copies,'macro events preserve the player cursor')
EditMacro(1,'renamed',3,nil);T.settle()
local shared=B:Get(62,nil,true);local macro=shared.macros[shared.slots[1].id]
assert(macro.name=='renamed' and macro.icon==3,'rename and selected icon changes are saved')
T.cursor=nil
for i=1,500 do T.emit('ACTIONBAR_SLOT_CHANGED',0);T.settle()end
assert(T.copies==copies,'passive slot notifications do not use cursor reads')
T.slots[3].id=200;T.emit('ACTIONBAR_SLOT_CHANGED',3);T.settle()
assert(B:Get(62,nil,true).slots[3].id==200,'ordinary slot edits persist in the current layout')
B:SetShared(62,'shared',false)
EditMacro(1,nil,nil,'/cast Shared edit');T.settle()
assert(T.body(B:Get(62,nil,true),1)=='/cast Shared edit' and not B:Get(62,'shared',false),'preference changes take effect on the next apply')
T.activate('other',false,initial)
local pool=T.slots[1].id
assert(pool>120 and T.native[pool].body=='/cast Alpha','earlier content uses a managed slot')
assert(T.body(B:Get(62,nil,true),1)=='/cast Shared edit','own writes cannot overwrite the outgoing shared layout')
EditMacro(pool,nil,nil,'/cast Independent edit');T.settle()
assert(T.body(B:Get(62,'other',false),1)=='/cast Independent edit')
assert(T.body(B:Get(62,nil,true),1)=='/cast Shared edit')
DeleteMacro(1);T.settle()
EditMacro(1,nil,nil,'/cast Beta edited');T.settle()
assert(T.body(B:Get(62,'other',false),2)=='/cast Beta edited','deletion compaction preserves the surviving binding')
assert(T.body(B:Get(62,nil,true),2)=='/cast Beta','inactive shared copy stays unchanged')
-- Both specs reuse native slots, while retaining their own macro definitions.
local spec62=B:Get(62,'other',false)
T.spec=63
local spec63=A.Macros.Copy(spec62);spec63.spec=63
spec63.macros[spec63.slots[1].id].body='/cast Fire'
assert(B:SeedDefault(63,spec63,'test'))
T.activate('fire',true,spec63);B.observedSpec=63
assert(T.native[T.slots[1].id].body=='/cast Fire')
T.spec=62;T.emit('ACTIVE_PLAYER_SPECIALIZATION_CHANGED');T.settle()
assert(not B.pendingSpec and T.native[T.slots[1].id].body=='/cast Independent edit')
assert(T.body(B:Get(63,nil,true),1)=='/cast Fire','other spec snapshot remains isolated')
local poolCount=#A.Store.character.macroPool
T.spec=63;T.emit('ACTIVE_PLAYER_SPECIALIZATION_CHANGED');T.settle()
assert(T.native[T.slots[1].id].body=='/cast Fire' and #A.Store.character.macroPool==poolCount)
T.frames={}
assert(loadfile('addon/LycheeTalent/ActionBars.lua'))('LycheeTalent',A);B=A.ActionBars;T.B=B
B:Init();T.emit('PLAYER_ENTERING_WORLD');T.settle()
assert(not B.pendingSpec and T.native[T.slots[1].id].body=='/cast Fire','reload restores the saved per-spec owner')
-- Spec changes are remembered even while an interrupted Apply still owns its
-- event handler; readiness is decided by subsequent native config events.
A.Apply.op={};T.spec=62;T.external=true
T.emit('ACTIVE_PLAYER_SPECIALIZATION_CHANGED');A.Apply.op=nil;T.settle()
assert(B.pendingSpec==62 and T.native[T.slots[1].id].body=='/cast Fire','do not touch another native config')
T.external=false;T.combat=true;T.emit('ACTIVE_COMBAT_CONFIG_CHANGED');T.settle()
assert(B.pendingSpec==62,'combat defers restoration')
T.combat=false;T.cursor={kind='item',id=789};T.emit('PLAYER_REGEN_ENABLED');T.settle()
assert(B.pendingSpec==62 and T.cursor.id==789,'occupied cursor defers restoration')
ClearCursor();T.settle()
assert(not B.pendingSpec and T.native[T.slots[1].id].body=='/cast Independent edit')
-- A failed spec restore reports once and retains the target for an explicit
-- retry. Its own delayed events must not create a retry loop or overwrite it.
T.spec=63;T.failEdit=true;T.emit('ACTIVE_PLAYER_SPECIALIZATION_CHANGED');T.settle()
assert(B.resumeFailed and T.body(B:Get(63,nil,true),1)=='/cast Fire')
local writes=T.writes
T.emit('ACTIONBAR_SLOT_CHANGED',0);T.emit('TRAIT_CONFIG_UPDATED');T.settle()
assert(T.writes==writes and B.pendingSpec==63)
T.activate('fire',true,B:Get(63,nil,true));B.resumeFailed=nil
T.cursor={kind='item',id=456};copies=T.copies
T.emit('PLAYER_LOGOUT');T.settle()
assert(T.cursor.id==456 and T.copies==copies)
print('PASS '..(arg[1]or 'synchronous')..' events: raw edits, slot saves, ownership, self writes, compaction, per-spec restore and reload')
