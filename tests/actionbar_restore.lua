local A={Store={character={}},GetSpec=function() return 62 end}
assert(loadfile('addon/LycheeTalent/ActionBars.lua'))('LycheeTalent',A)
local B=A.ActionBars
local slots={};for i=1,180 do slots[i]={} end
slots[1]={kind='spell',id=100,sub='spell'}
slots[2]={kind='item',id=200}
local cursor,combat,placements=nil,false,0
local function copy(t)local r={};for k,v in pairs(t or {})do r[k]=v end;return r end
InCombatLockdown=function()return combat end
GetCursorInfo=function()return cursor and cursor.kind end
ClearCursor=function()cursor=nil end
GetActionInfo=function(i)local s=slots[i];return s.kind,s.id,s.sub end
C_Spell={PickupSpell=function(id)cursor={kind='spell',id=id,sub='spell'} end}
C_Item={PickupItem=function(id)cursor={kind='item',id=id}end}
C_ActionBar={}
PickupAction=function(i)cursor=slots[i];slots[i]={}end
local failOnce=false
PlaceAction=function(i)
 placements=placements+1
 if failOnce then failOnce=false;error('injected placement failure')end
 local old=slots[i];slots[i]=cursor;cursor=old.kind and old or nil
end
local before=assert(B:Capture(62))
local desired=assert(B:Capture(62));desired.slots[1],desired.slots[2]=desired.slots[2],desired.slots[1]
assert(B:Restore(desired));assert(slots[1].id==200 and slots[2].id==100)
assert(B:Restore(before));assert(slots[1].id==100 and slots[2].id==200)
local originalPlacements=placements
cursor={kind='item',id=999}
local ok,why=B:Restore(desired)
assert(not ok and why=='BARS_CURSOR' and cursor.id==999 and placements==originalPlacements,'existing cursor preserved')
cursor=nil;combat=true
assert(not B:Restore(desired) and placements==originalPlacements,'combat causes no writes');combat=false
local unknown=assert(B:Capture(62));unknown.slots[2]={kind='unsupported',id=3}
assert(not B:Restore(unknown) and placements==originalPlacements,'unsupported preflight causes no writes')
failOnce=true
local restored,reason,detail=B:Restore(desired)
assert(not restored and reason=='BARS_RESTORE' and detail.rolledBack,'failed placement reports rollback')
assert(slots[1].id==100 and slots[2].id==200 and not cursor,'failed restore preserves previous slots')
local empty=assert(B:Capture(62));empty.slots[1]={}
assert(B:Restore(empty) and not slots[1].kind,'empty slots are restored explicitly')
assert(B:Restore(before) and slots[1].id==100,'cleared slot can be restored')
local pickup=C_Spell.PickupSpell
C_Spell.PickupSpell=function(id)if id~=100 then pickup(id)end end
assert(B:Restore(desired),'existing unlearned spell must be movable without recreating it')
assert(slots[2].id==100 and slots[1].id==200 and not cursor)
assert(B:Restore(before) and slots[1].id==100,'unlearned spell survives roundtrip')
failOnce=true
local restoredUnlearned,_,failedUnlearned=B:Restore(desired)
assert(not restoredUnlearned and failedUnlearned.rolledBack and slots[1].id==100 and slots[2].id==200 and not cursor,'failed swap preserves the only unavailable spell instance')
local replace=assert(B:Capture(62));replace.slots[1]={kind='item',id=999};replace.slots[3]=copy(before.slots[1])
assert(B:Restore(replace) and slots[1].id==999 and slots[3].id==100,'move unavailable spell before replacing its original slot')
assert(B:Restore(before) and slots[1].id==100 and not slots[3].kind)
C_Spell.PickupSpell=pickup
print('PASS action-bar restore: swaps, empty slots, cursor, combat, preflight rejection and rollback')
