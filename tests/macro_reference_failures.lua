local runtime=assert(loadfile("tests/macro_runtime.lua"))()
local function setup()
 local T=runtime(false)
 T.native[1]={name="a",icon=1,body="/say a"};T.native[2]={name="b",icon=2,body="/say b"}
 T.slots[1]={kind="macro",id=1};T.slots[2]={kind="spell",id=10}
 local target=assert(T.B:Capture(T.spec))
 local second=target.macros[target.slots[1].id].nativeID
 local source=T.A.Macros:Pack({spec=T.spec,slots={{kind="macro",id=2}}})
 local ref=source.slots[1].id;target.macros[ref]=source.macros[ref]
 target.slots[1]={kind="macro",id=ref};target.slots[2]={kind="macro",id=second}
 return T,target
end
local T,target=setup();T.failPlace=true
local ok,why,detail=T.B:Restore(target)
assert(not ok and why=="BARS_RESTORE" and detail.rolledBack)
assert(T.slots[1].id==1 and T.slots[2].id==10 and not T.B.verified and T.writes==0)
assert(not T.B.pendingSpec,"successful slot rollback does not pause autosave")
-- A target macro disappearing during native placement must not report success.
T,target=setup();local place=PlaceAction;local injected=false
PlaceAction=function(slot)
 place(slot)
 if not injected then injected=true;DeleteMacro(2) end
end
ok,why,detail=T.B:Restore(target)
assert(not ok and detail.rolledBack and T.slots[1].id==1 and T.slots[2].id==10)
assert(target.macros[target.slots[1].id].body=="/say b" and T.writes==0)
-- A failed rollback retains the requested target and blocks background saves.
T,target=setup();place=PlaceAction
PlaceAction=function(slot)if slot==2 then error("native rejected placement and rollback")end;return place(slot)end
ok,why,detail=T.B:Restore(target)
assert(not ok and not detail.rolledBack and T.B.pendingSpec==T.spec and T.B.resumeFailed)
assert(T.B.recovery.requested.macros[target.slots[1].id].body=="/say b" and not T.B.verified)
assert(T.native[1].body=="/say a" and T.native[2].body=="/say b" and T.writes==0)
print("PASS reference restore failures: slot rollback, disappearing native macro, incomplete rollback preserves target and pauses ownership")
