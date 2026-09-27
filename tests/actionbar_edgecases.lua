local A={Store={character={}},GetSpec=function()return 62 end}
assert(loadfile("addon/LycheeTalent/ActionBars.lua"))("LycheeTalent",A)
local B=A.ActionBars
local slots={};for i=1,180 do slots[i]={}end
local cursor,override,unavailable,failAt,sideEffect=nil,false,false,nil,nil
local function copy(t)local r={};for k,v in pairs(t or {})do r[k]=v end;return r end
InCombatLockdown=function()return false end
GetCursorInfo=function()return cursor and cursor.kind end
ClearCursor=function()cursor=nil end
GetActionInfo=function(i)local s=slots[i];return s.kind,s.id,s.sub end
C_ActionBar={}
C_Spell={
 GetBaseSpell=function(id)return id==101 and 100 or id end,
 PickupSpell=function(id)
  if unavailable and (id==100 or id==101)then return end
  cursor={kind="spell",id=override and id==100 and 101 or id,sub="spell"}
 end,
}
C_Item={PickupItem=function(id)cursor={kind="item",id=id}end}
PickupAction=function(i,keep)
 cursor=slots[i].kind and copy(slots[i]) or nil
 if not keep then slots[i]={}end
end
PlaceAction=function(i)
 if failAt==i then failAt=nil;error("injected placement failure")end
 local old=slots[i];slots[i]=copy(cursor);cursor=old.kind and old or nil
 if sideEffect then slots[180]={kind="item",id=999};sideEffect=nil end
end
local function reset()
 for i=1,180 do slots[i]={}end
 cursor=nil;override=false;unavailable=false;failAt=nil;sideEffect=nil
end
local function assertLayout(snapshot)
 for i=1,180 do
  assert(slots[i].kind==snapshot.slots[i].kind and slots[i].id==snapshot.slots[i].id,"wrong final slot "..i)
 end
 assert(not cursor,"cursor must be clean")
end
if arg[1]=="override" then
 reset();slots[1]={kind="item",id=200}
 local target=assert(B:Capture(62));target.slots[1]={kind="spell",id=100,sub="spell"}
 override=true
 local ok,why,detail=B:Restore(target)
 assert(ok,"valid base-to-override restore rejected: "..tostring(why).." "..tostring(detail and detail.reason))
 assert(slots[1].id==101 and not cursor)
 -- A different spell must still be replaced; pet spell subtypes stay distinct.
 override=false
 target.slots[1]={kind="spell",id=102,sub="spell"}
 assert(B:Restore(target));assert(slots[1].id==102)
 target.slots[1]={kind="spell",id=102,sub="pet"}
 local rejected,reason=B:Restore(target)
 assert(not rejected and reason=="BARS_RESTORE")
 print("PASS overridden spell accepted through native base-spell mapping")
else
 reset();slots[1]={kind="spell",id=100,sub="spell"}
 local target=assert(B:Capture(62));target.slots[2]=copy(target.slots[1])
 assert(B:Restore(target));assertLayout(target)
 reset();slots[1]={kind="spell",id=100,sub="spell"}
 target=assert(B:Capture(62));target.slots[1]={};target.slots[2]=copy(slots[1]);target.slots[3]=copy(slots[1])
 unavailable=true
 assert(B:Restore(target));assertLayout(target)
 reset();slots[1]={kind="spell",id=100,sub="spell"};slots[2]={kind="item",id=200}
 local before=assert(B:Capture(62))
 target=assert(B:Capture(62));target.slots[2]=copy(slots[1]);target.slots[3]={kind="item",id=300}
 failAt=3
 local ok,why,detail=B:Restore(target)
 assert(not ok and why=="BARS_RESTORE" and detail.rolledBack,"rollback must succeed")
 assertLayout(before)
 -- A side effect outside the changed slots must not be reported as success,
 -- nor may rollback claim the original layout was restored when it was not.
 reset();target=assert(B:Capture(62));target.slots[1]={kind="item",id=300}
 sideEffect=true
 ok,why,detail=B:Restore(target)
 assert(not ok and why=="BARS_RESTORE" and not detail.rolledBack)
 assert(detail.reason:find("BARS_LAYOUT_VERIFY:180",1,true) and not cursor)
 print("PASS duplicate actions preserve existing slots, unlearned duplicates, rollback")
end
