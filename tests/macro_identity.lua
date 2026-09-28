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
assert(not a.name and not a.body,"new snapshots store macro indices, not macro text")
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
-- Old layouts must also use the current macro at the recorded index.
local legacy=assert(B:Capture(62))
legacy.slots[1]={kind="macro",id=2,name="old name",body="old body",character=true,macroInvalid=true}
legacy.slots[2]={kind="macro",id=1,name="old name",body="old body",macroInvalid=true}
macros[1]={"renamed","/cast Changed\n"}
macros[2]={"renamed","/cast Changed\n"}
assert(B:MacroIndex(legacy.slots[1])==2 and B:MacroIndex(legacy.slots[2])==1,
 "old names, bodies, scope flags and invalidation markers must not block original indices")
assert(B:Restore(legacy) and slots[1]==2 and slots[2]==1 and slots[3]==121,
 "even identical macros restore to their exact saved positions")
assert(macros[1][1]=="renamed" and macros[1][2]=="/cast Changed\n","restore does not edit macro contents")
-- A changed macro already at the desired action slot is a no-op.
assert(B:Restore(legacy) and not cursor,"changed content in place does not trigger a false failure")
-- An actually empty macro index still fails before changing any action slot.
slots[2]=2;macros[1]=nil
local before1,before2=slots[1],slots[2]
local ok,reason=B:Restore(legacy)
assert(not ok and reason=="BARS_MACRO" and slots[1]==before1 and slots[2]==before2 and not cursor,
 "empty recorded index does not fall back to another same-name macro or change bars")
-- Deleting/recreating a macro at that position intentionally uses the new one.
macros[1]={"replacement","/say New macro"}
assert(B:Restore(legacy) and slots[2]==1,"recreated macro at the recorded index is usable without resaving")
assert(B:MacroIndex(c)==121,"absolute index preserves character macro range")
assert(not B:MacroIndex({id=0}) and not B:MacroIndex({id=1.5}),"invalid indices are rejected")
print("PASS macro slots: edited/renamed/recreated macros, legacy flags, duplicate names/bodies, missing index, cursor and combat")
