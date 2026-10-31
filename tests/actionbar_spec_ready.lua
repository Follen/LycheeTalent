-- Production UPDATE_MACROS dispatch while native specialization is not ready.
local runtime=assert(loadfile("tests/macro_runtime.lua"))()
local T=runtime(true);local A,B=T.A,T.B
T.spec=0;B:Init()
local ok,why=pcall(T.emit,"UPDATE_MACROS")
print("SPEC_READY spec=0 UPDATE_MACROS ok="..tostring(ok).." reason="..tostring(why))
assert(ok,"early UPDATE_MACROS must not index a missing specialization state")
T.spec=nil;assert(pcall(T.emit,"UPDATE_MACROS"));assert(not B:Owner())
T.emit("CURSOR_CHANGED");T.settle();assert(not B:Owner())
-- No game macro reads while specialization is unavailable, including Init.
local R=runtime(true);R.spec=0
local read=GetMacroInfo;local reads=0
GetMacroInfo=function(...)reads=reads+1;return read(...)end
R.B:Init();R.emit("UPDATE_MACROS");R.emit("PLAYER_ENTERING_WORLD");R.settle()
assert(reads==0,"unready initialization must defer native macro synchronization")
R.spec=62;R.native[1]={name="Current",icon=1,body="/say ready"};R.slots[1]={kind="macro",id=1}
R.emit("ACTIVE_PLAYER_SPECIALIZATION_CHANGED");R.settle()
local snapshot=assert(R.B:Capture(62))
assert(R.B:SeedDefault(62,snapshot,"fixture"));R.activate("ready",true,snapshot)
R.emit("UPDATE_MACROS");assert(reads>0)
EditMacro(1,nil,nil,"/say edited after readiness");R.settle()
local saved=assert(R.B:Get(62,nil,true))
assert(saved.macros[saved.slots[1].id].body=="/say edited after readiness","normal updates resume after spec initialization")
R.slots[2]={kind="spell",id=321};R.emit("ACTIONBAR_SLOT_CHANGED",2);R.settle()
assert(R.B:Get(62,nil,true).slots[2].id==321,"normal slot observations remain enabled")
assert(R.writes==1 and R.placements==0,"passive callbacks never place actions or modify native macros")
print("PASS specialization readiness: spec0/nil macro event safe, native synchronization deferred, later macro/slot updates resume")
