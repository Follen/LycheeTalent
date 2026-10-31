local runtime=assert(loadfile("tests/macro_runtime.lua"))()
local T=runtime(false);local B,M=T.B,T.A.Macros
for i=1,150 do T.native[i]={name="Macro"..i,icon=i,body="/say "..i} end
T.slots[1]={kind="macro",id=1};T.slots[2]={kind="macro",id=121}
local target=assert(B:Capture(T.spec))
local id=target.macros[target.slots[1].id].nativeID
T.slots[1]={kind="spell",id=99}
assert(B:Restore(target));assert(T.slots[1].id==1 and T.writes==0,"full native macro table reuses references")
-- Global native edits are shared, including layouts whose backup is older.
EditMacro(1,nil,nil,"/say shared latest")
assert(B:Restore(target));assert(T.body(B.verified,1)=="/say shared latest")
assert(target.macros[target.slots[1].id].body=="/say 1","old backup is never written back")
assert(T.writes==1 and M:Resolve(target.macros[target.slots[1].id],M:Current())==1)
-- Deleting an earlier macro renumbers existing references.
M:Current();DeleteMacro(120);M:Current()
assert(B:Restore(target) and T.slots[2].id==121,"character scope is separate")
DeleteMacro(1);M:Current()
T.slots[1]={kind="item",id=77}
local ok,why,detail=B:Restore(target)
assert(ok and detail.missingMacros[1]==1 and T.slots[1].kind=="item" and T.slots[1].id==77)
assert(B.verified.pendingMacros[1].macro.nativeID==id,"missing reference retains backup and slot")
T.native[1]={name="Replacement",icon=1,body="/say unrelated"};M:Current()
assert(B:Restore(target) and T.slots[1].id==77,"recycled index is not adopted")
-- A duplicate-name edit cannot be inferred from its name.
local D=runtime(false)
D.native[1]={name="same",icon=1,body="/say a"};D.native[2]={name="same",icon=1,body="/say b"}
D.slots[1]={kind="macro",id=1};local duplicate=assert(D.B:Capture(D.spec))
EditMacro(1,nil,nil,"/say edited");D.A.Macros:Current()
local _,missing=D.A.Macros:Physical(duplicate);assert(missing[1],"ambiguous identity is unresolved")
-- Native API line-ending representation does not invalidate an observed ID.
local L=runtime(false);L.native[121]={name="Existing",icon=1,body="/say current"}
L.slots[1]={kind="macro",id=121};local saved=assert(L.B:Capture(L.spec))
L.native[121].body="/say current\n";L.A.Macros.character=nil
CreateMacro=function()error("plugin must never create a native macro")end
EditMacro=function()error("plugin must never edit a native macro")end
DeleteMacro=function()error("plugin must never delete a native macro")end
assert(L.B:Restore(saved) and L.slots[1].id==121 and L.writes==0)
assert(not L.A.Macros.Link and not L.A.Macros.Plan and not L.A.Macros.Execute and not L.A.Macros.Rollback)
print("PASS native references: full capacity, shared edits, deletion, ambiguity, native LF representation, no macro writes")
