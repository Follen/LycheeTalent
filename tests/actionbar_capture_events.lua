local runtime=assert(loadfile("tests/macro_runtime.lua"))()
for _,deferred in ipairs({false,true}) do
 local T=runtime(deferred);local B,M=T.B,T.A.Macros
 T.native[1]={name="a",icon=1,body="/say a"};T.native[2]={name="b",icon=2,body="/say b"}
 T.slots[1]={kind="macro",id=2};local shared=assert(B:Capture(T.spec))
 assert(B:SeedDefault(T.spec,shared,"test"));T.activate("shared",true,shared);B:Init()
 local cursor={kind="item",id=42};T.cursor=cursor
 local copies=T.copies
 EditMacro(2,nil,nil,"/say latest");T.settle()
 assert(T.cursor==cursor and T.copies==copies,"macro observation never touches cursor")
 T.cursor=nil
 assert(T.body(B:Get(T.spec,nil,true),1)=="/say latest")
 local id=B:Get(T.spec,nil,true).macros[B:Get(T.spec,nil,true).slots[1].id].nativeID
 DeleteMacro(1);T.settle();assert(T.slots[1].id==1)
 assert(B:Restore(shared) and T.slots[1].id==1,"renumbered identity survives")
 DeleteMacro(1);T.settle()
 local saved=B:Get(T.spec,nil,true)
 assert(B:Spec(T.spec).applied.partial and saved.pendingMacros[1] and saved.pendingMacros[1].macro.nativeID==id,"native deletion keeps recoverable backup")
 T.slots[1]={kind="spell",id=123};T.emit("ACTIONBAR_SLOT_CHANGED",1);T.settle()
 assert(not B:Spec(T.spec).applied.partial and not B:Get(T.spec,nil,true).pendingMacros,"manual replacement resolves pending slot")
 assert(T.writes==1,"only simulated user edit writes native macros")
end
-- Layout ownership remains per specialization; native macro bodies are shared.
local T=runtime(true);local B,M=T.B,T.A.Macros
T.native[1]={name="shared native",icon=1,body="/say original"}
T.native[2]={name="other",icon=2,body="/say other"}
T.slots[1]={kind="macro",id=1}
local first=assert(B:Capture(62));assert(B:SeedDefault(62,first,"test"));T.activate("first",true,first);B:Init()
T.spec=63;T.slots[1]={kind="macro",id=2}
local second=assert(B:Capture(63));assert(B:SeedDefault(63,second,"test"));T.activate("second",true,second)
T.emit("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");T.settle()
EditMacro(1,nil,nil,"/say globally edited");T.settle()
assert(T.body(B:Get(62,nil,true),1)=="/say original","inactive backup is not mistaken for native content authority")
M.character=nil;M:Initialize() -- persisted references survive a reload with unchanged native identity
T.spec=62;T.slots[1]={kind="spell",id=999}
T.emit("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");T.settle()
assert(T.slots[1].kind=="macro" and T.slots[1].id==1 and T.native[1].body=="/say globally edited")
assert(T.body(B:Get(63,nil,true),1)=="/say other","specialization return cannot save into departed layout")
assert(not B.pendingSpec and not B.resumeFailed and T.writes==1)
print("PASS native macro observation: synchronous/deferred edits, renumbering, recoverable deletion, manual replacement")
