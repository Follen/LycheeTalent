-- Cursor appearance/held-content notifications do not imply slot mutation.
local T=assert(loadfile("tests/macro_runtime.lua"))()(true)
local A,B=T.A,T.B
T.native[1]={name="Current",icon=1,body="/say current"};T.slots[1]={kind="macro",id=1}
local initial=assert(B:Capture(T.spec));assert(B:SeedDefault(T.spec,initial,"fixture"));T.activate("owned",true,initial);B:Init()
local captures,saves=0,0
local capture,save=B.Capture,B.SaveLayout
B.Capture=function(self,...)captures=captures+1;return capture(self,...)end
B.SaveLayout=function(self,...)saves=saves+1;return save(self,...)end
for i=1,100 do T.emit("CURSOR_CHANGED",true,1,0,0);T.settle()end
print("CURSOR_OBSERVATION normal100 captures="..captures.." saves="..saves)
assert(captures==0 and saves==0,"ordinary cursor state changes must not capture/save the entire action layout")
local held={kind="item",id=777};T.cursor=held
T.slots[2]={kind="spell",id=123};T.emit("ACTIONBAR_SLOT_CHANGED",2);T.settle()
assert(captures==1 and saves==1 and T.cursor==held,"actual slot event still saves without touching the held cursor")
assert(B:Get(T.spec,nil,true).slots[2].id==123)
T.slots[1]={kind="spell",id=999};B.pendingSpec=T.spec;B.resumeFailed=nil
local before=captures
T.emit("CURSOR_CHANGED",false,1,0,0);T.settle()
assert(B.pendingSpec==T.spec and captures==before and T.cursor==held,"pending spec waits while cursor is occupied")
T.cursor=nil;T.emit("CURSOR_CHANGED",true,0,1,777);T.settle()
assert(not B.pendingSpec and T.slots[1].kind=="macro" and T.slots[1].id==1 and not T.cursor,"clear cursor resumes the pending specialization layout")
assert(captures>before)
B.pendingSpec=T.spec;B.resumeFailed=true;T.slots[1]={kind="spell",id=456}
before=captures;T.emit("CURSOR_CHANGED",true,0,1,777);T.settle()
assert(captures==before and B.pendingSpec==T.spec and B.resumeFailed and T.slots[1].id==456,"failed recovery remains manual-only")
B.pendingSpec=nil;B.resumeFailed=nil
EditMacro(1,nil,nil,"/say shared updated");T.settle()
assert(A.Macros.registry.records[initial.macros[initial.slots[1].id].nativeID].native.body=="/say shared updated","macro notifications still synchronize global references")
print("PASS cursor event split: ordinary cursor is inert; actual slots save; pending clear-cursor resumes; failed recovery stays paused; macro updates remain independent")
