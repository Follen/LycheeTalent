-- Replay the reported API result: GetActionInfo says macro, copied pickup
-- succeeds, but GetCursorInfo returns nothing at 77, 78, 113 and 114.
local A={Store={character={}},GetSpec=function()return 62 end}
assert(loadfile('addon/LycheeTalent/ActionBars.lua'))('LycheeTalent',A)
local B=A.ActionBars
local slots={};for i=1,180 do slots[i]={} end
local blocked={77,78,113,114}
for _,i in ipairs(blocked)do slots[i]={kind='macro',id=999,unreadable=true}end
slots[1]={kind='macro',id=129};slots[5]={kind='macro',id=127}
local cursor,combat,throwPickup,wrongType,placements=nil,false,false,false,0
local function copy(t)local out={};for k,v in pairs(t)do out[k]=v end;return out end
function InCombatLockdown()return combat end
function GetCursorInfo()if cursor then return cursor.kind,cursor.id end end
function ClearCursor()cursor=nil end
function GetActionInfo(i)local s=slots[i];return s.kind,s.id end
function GetMacroInfo(i)if i==129 or i==127 then return 'same name',1,'same body' end end
function PickupAction(i,keep)
 if throwPickup then error('pickup exception')end
 if wrongType then cursor={kind='spell',id=123};return end
 if slots[i].unreadable then assert(keep==true,'unreadable action must never be removed');return end
 cursor=slots[i].kind and copy(slots[i])or nil
 if not keep then slots[i]={}end
end
function PickupMacro(i)cursor={kind='macro',id=i}end
local failOnce=false
function PlaceAction(i)
 assert(not slots[i].unreadable,'unreadable action must never be overwritten')
 placements=placements+1
 if failOnce then failOnce=false;error('placement failure')end
 local old=slots[i];slots[i]=copy(cursor);cursor=old.kind and copy(old)or nil
end
local before,reason,failedSlot=B:Capture(62)
assert(before,'capture must survive the observed empty cursor response: '..tostring(reason)..' at '..tostring(failedSlot))
assert(before.slots[1].id==129 and before.slots[5].id==127,'readable macros keep exact indices')
for _,i in ipairs(blocked)do
 assert(before.slots[i].kind=='unreadableMacro' and before.slots[i].id==i,'unresolved slot is not an empty slot or a guessed macro index')
end
assert(B:Valid(before,62) and not cursor)
assert(B:SeedDefault(62,before,'test'))
assert(B:SaveIndependent(62,'a',before))
local desired=assert(B:Get(62,'a',false))
desired.slots[1],desired.slots[5]=desired.slots[5],desired.slots[1]
desired.slots[77]={kind='macro',id=129};desired.slots[78]={}
local ok,why,detail=B:Restore(desired)
assert(ok and detail and table.concat(detail.preservedSlots,',')=='77,78,113,114','report every preserved slot')
assert(slots[1].id==127 and slots[5].id==129,'other macro slots restore normally')
for _,i in ipairs(blocked)do assert(slots[i].unreadable,'preserve unreadable slots regardless of desired contents')end
assert(B:Restore(before) and slots[1].id==129 and slots[5].id==127,'default/independent roundtrip')
local count=placements
assert(B:Restore(before) and placements==count,'same layout with unreadable macros needs no writes')
failOnce=true
ok,why,detail=B:Restore(desired)
assert(not ok and why=='BARS_RESTORE' and detail.rolledBack,'normal restore failures still roll back')
assert(slots[1].id==129 and slots[5].id==127 and not cursor)
-- Once the user replaces an unreadable slot, an old placeholder cannot clear it.
slots[77]={kind='macro',id=127}
ok,why,detail=B:Restore(before)
assert(ok and slots[77].id==127,'saved placeholder preserves a now-readable action')
local fresh=assert(B:Capture(62))
assert(fresh.slots[77].kind=='macro' and fresh.slots[77].id==127,'new capture resumes normal management')
fresh.slots[77]={kind='macro',id=129}
assert(B:Restore(fresh) and slots[77].id==129,'refreshed slot restores normally')
before.slots[77].id=78
assert(not B:Valid(before,62),'placeholder is bound to its original action slot')
-- Do not turn every read failure into a successful partial restore.
throwPickup=true
assert(not B:Capture(62),'actual pickup exceptions still stop capture');throwPickup=false
wrongType=true
assert(not B:Capture(62),'wrong cursor type still stops capture');wrongType=false
cursor={kind='item',id=1}
ok,why=B:Capture(62)
assert(not ok and why=='BARS_CURSOR' and cursor.id==1,'existing cursor must be preserved');cursor=nil
combat=true
ok,why=B:Capture(62)
assert(not ok and why=='COMBAT','combat guard remains intact')
print('PASS unreadable macro slots: observed nil cursor, exact IDs, preservation, partial report, roundtrip, rollback, recovery and guards')
