local A={Store={character={}},GetSpec=function()return 62 end}
assert(loadfile("addon/LycheeTalent/ActionBars.lua"))("LycheeTalent",A)
local B=A.ActionBars
MAX_ACCOUNT_MACROS=120
local macros={[1]={"same","/cast Alpha"},[2]={"same","/cast Beta"},[121]={"same","/cast Alpha"}}
local slots={[1]=1,[2]=2,[3]=121}
local cursor,combat,fail,reads=nil,false,false,0
InCombatLockdown=function()return combat end
GetNumMacros=function()return 2,1 end
GetActionInfo=function(slot)if slots[slot] then return "macro",999,"spell" end end
C_ActionBar={GetActionText=function()return "same" end}
GetMacroIndexByName=function()return 1 end
GetMacroInfo=function(i)local m=macros[i];if m then return m[1],134400,m[2] end end
GetCursorInfo=function()if cursor then return cursor.kind,cursor.id end end
ClearCursor=function()cursor=nil end
PickupAction=function(slot,copy)
 reads=reads+1
 cursor={kind="macro",id=slots[slot]}
 if copy~=true then slots[slot]=nil end
 if fail then error("injected pickup failure") end
end
PickupMacro=function(i)cursor={kind="macro",id=i}end
local a=assert(B:ReadSlot(1))
local b=assert(B:ReadSlot(2))
local c=assert(B:ReadSlot(3))
assert(a.id==1 and b.id==2 and c.id==121,"exact macro indices")
assert(a.body~=b.body and c.character and not a.character,"same names preserve body and scope")
assert(slots[1]==1 and slots[2]==2 and slots[3]==121 and not cursor,"capture leaves bars and cursor intact")
local snapshot=assert(B:Capture(62))
snapshot.slots[1],snapshot.slots[2]=snapshot.slots[2],snapshot.slots[1]
PlaceAction=function(slot)
 local previous=slots[slot]
 slots[slot]=cursor and cursor.id
 cursor=previous and {kind="macro",id=previous} or nil
end
assert(B:Restore(snapshot) and slots[1]==2 and slots[2]==1 and slots[3]==121 and not cursor,"restore swaps same-name macros without changing scope")
slots[1],slots[2]=1,2
local oldReads=reads
cursor={kind="item",id=123}
local ok,why=B:ReadSlot(1)
assert(not ok and why=="BARS_CURSOR" and cursor.id==123 and reads==oldReads,"occupied cursor preserved")
cursor=nil;combat=true
ok,why=B:ReadSlot(1)
assert(not ok and why=="COMBAT" and reads==oldReads,"no protected pickup in combat")
combat=false;fail=true
ok,why=B:ReadSlot(1)
assert(not ok and not cursor and slots[1]==1,"failed copied pickup cleans cursor without removing action")
fail=false
-- Equal text does not make two macro slots interchangeable.
macros[2]={"same","/cast Alpha"}
local identical=assert(B:Capture(62))
identical.slots[1],identical.slots[2]=identical.slots[2],identical.slots[1]
assert(B:Restore(identical) and slots[1]==2 and slots[2]==1,
 "identical macros must restore their exact saved indices")
macros[1]={"other","/cast Beta"}
assert(not B:MacroIndex(a),"changed original index must not fall back to identical macro")
local before1,before2=slots[1],slots[2]
local invalid=assert(B:Capture(62));invalid.slots[1]=a
assert(not B:Restore(invalid) and slots[1]==before1 and slots[2]==before2 and not cursor,
 "unresolved identity must fail before touching any slot")
macros[1]=nil
assert(not B:MacroIndex(a),"deleted original index must not fall back to another macro")
assert(B:MacroIndex(c)==121,"character macro keeps its own index")
-- A live saved profile retained a final LF that GetMacroInfo no longer returns.
macros[1]={"same","/cast Alpha"};slots[1],slots[2]=1,2
local newlineSnapshot=assert(B:Capture(62))
newlineSnapshot.slots[1].body=newlineSnapshot.slots[1].body.."\n"
assert(B:Restore(newlineSnapshot) and slots[1]==1 and slots[2]==2 and not cursor,
 "a removed final newline must not report BARS_MACRO or substitute a macro")
newlineSnapshot.slots[1].body="/cast Alpha\r\n\r\n"
assert(B:MacroIndex(newlineSnapshot.slots[1])==1,"terminal CRLF is also formatting")
newlineSnapshot.slots[1].body="/cast\nAlpha"
assert(not B:MacroIndex(newlineSnapshot.slots[1]),"internal newlines remain significant")
newlineSnapshot.slots[1].body="/cast Alpha "
assert(not B:MacroIndex(newlineSnapshot.slots[1]),"do not broaden normalization to arbitrary whitespace")
print("PASS exact macro identity: identical-body swaps, changed/deleted index rejection, cursor, combat and cleanup")
