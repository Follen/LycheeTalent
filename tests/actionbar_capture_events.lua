local cursor,frames,timers,pickups,macroID,readError=nil,{},{},0,1,false
local A={Store={character={applied={spec=62,id='active',shared=false}}},GetSpec=function()return 62 end,
 Apply={CurrentBuildID=function()return 'active' end}}
local function emit(event,slot)
 for _,frame in ipairs(frames)do if frame[event]then frame.handler(frame,event,slot)end end
end
function InCombatLockdown()return false end
function GetActionInfo(slot)
 if readError then error('injected action read failure')end
 if slot==1 then return 'macro',999,'spell' end
end
function GetMacroInfo(index)if index==1 or index==2 then return 'Macro',134400,'/cast Test' end end
function GetCursorInfo()if cursor then return cursor.kind,cursor.id end end
function ClearCursor()cursor=nil end
function PickupAction(slot,keep)
 assert(slot==1 and keep==true,'capture must copy the macro')
 pickups=pickups+1;cursor={kind='macro',id=macroID}
 -- A native or addon-triggered notification during copied macro pickup.
 emit('ACTIONBAR_SLOT_CHANGED',slot)
end
function CreateFrame()
 local frame={};frames[#frames+1]=frame
 function frame:RegisterEvent(event)self[event]=true end
 function frame:SetScript(_,fn)self.handler=fn end
 return frame
end
C_Timer={NewTimer=function(_,fn)local t={fn=fn};timers[#timers+1]=t;return t end}
assert(loadfile('addon/LycheeTalent/ActionBars.lua'))('LycheeTalent',A)
local B=A.ActionBars
B:Spec(62).default={}
B:Init()
emit('ACTIONBAR_SLOT_CHANGED',1)
for frame=1,20 do
 local pending=timers;timers={}
 for _,timer in ipairs(pending)do timer.fn()end
end
print('idle frame captures='..pickups..', pending timers='..#timers)
assert(pickups==1 and #timers==0,'copied macro pickup must not keep mounting cursor icons every idle frame')
assert(not cursor,'capture must leave the cursor clear')
assert(B:Get(62,'active',false).slots[1].id==1,'save must preserve the exact macro index')
macroID=2
emit('ACTIONBAR_SLOT_CHANGED',1)
emit('ACTIONBAR_SLOT_CHANGED',1)
local pending=timers;timers={}
for _,timer in ipairs(pending)do timer.fn()end
assert(pickups==2 and #timers==0,'later user changes must still save once')
assert(B:Get(62,'active',false).slots[1].id==2,'same-name macro replacement must save its new exact index')
readError=true;emit('ACTIONBAR_SLOT_CHANGED',1)
pending=timers;timers={}
local ok,why=pcall(pending[1].fn)
assert(not ok and tostring(why):find('injected action read failure',1,true),'save errors must remain visible')
assert(not B.saveTimer,'a failed save must release its event guard')
readError=false;emit('ACTIONBAR_SLOT_CHANGED',1)
pending=timers;timers={};pending[1].fn()
assert(pickups==3 and #timers==0 and not B.saveTimer,'saving must resume after an API error')
print('PASS capture notifications: one save, exact macro identity, clear cursor, no event feedback')
