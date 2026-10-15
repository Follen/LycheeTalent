-- Independent slot refreshes must never start cursor work after Apply.
-- CURSOR_CHANGED is synchronous; slot notifications can be immediate or delayed.
local deferred=arg[1]=='deferred'
local cursor,frames,timers=nil,{},{}
local pickups,display,combat,readError,rejectDrop=0,999,false,false,false
local A={Store={character={applied={spec=62,id='active',shared=false}}},GetSpec=function()return 62 end,
 Apply={CurrentBuildID=function(self)if not self.op then return 'active' end end}}
local slots={[1]={kind='macro',id=1},[2]={kind='macro',id=121},[3]={kind='spell',id=100,sub='spell'}}
local macros={[1]='same',[2]='same',[121]='same'}
local function copy(t)local r={};for k,v in pairs(t or {})do r[k]=v end;return r end
local function emit(event,...)
 for _,frame in ipairs(frames)do if frame[event]then frame.handler(frame,event,...)end end
end
local function changed(slot)
 if deferred then timers[#timers+1]=function()emit('ACTIONBAR_SLOT_CHANGED',slot)end
 else emit('ACTIONBAR_SLOT_CHANGED',slot)end
end
local function settle()
 for frame=1,20 do local pending=timers;timers={};for _,fn in ipairs(pending)do fn()end end
 assert(#timers==0,'no background capture loop may remain')
end
local function setCursor(value)
 local old=cursor;cursor=value
 emit('CURSOR_CHANGED',not value,value and (value.kind=='macro' and 7 or 1)or 0,
  old and (old.kind=='macro' and 7 or 1)or 0,99999) -- never assume virtual IDs are macro indices
end
function InCombatLockdown()return combat end
function GetActionInfo(slot)
 if readError then error('injected action read failure')end
 local s=slots[slot]or{}
 if s.kind=='macro' then return 'macro',display,'spell' end
 return s.kind,s.id,s.sub
end
function GetMacroInfo(index)if macros[index]then return macros[index],134400,'/cast Same' end end
function GetNumMacros()
 local account,character=0,0
 for id in pairs(macros)do if id<=120 then account=account+1 else character=character+1 end end
 return account,character
end
function GetCursorInfo()if cursor then return cursor.kind,cursor.id end end
function ClearCursor()setCursor(nil)end
function PickupAction(slot,keep)
 if keep then
  pickups=pickups+1
  assert(A.Apply.op,'the addon must not pick up macros outside Applying')
 end
 local value=slots[slot];setCursor(value and value.kind and copy(value)or nil)
 if not keep then slots[slot]={}end
 changed(slot)
end
function PickupMacro(index)setCursor({kind='macro',id=index})end
function PlaceAction(slot)
 if not cursor or rejectDrop then return end
 local old=slots[slot];slots[slot]=copy(cursor)
 setCursor(old and old.kind and copy(old)or nil);changed(slot)
end
function DeleteMacro(index)
 if not macros[index]then return end
 macros[index]=nil
 for id=index+1,120 do macros[id-1]=macros[id];macros[id]=nil end
 for slot,s in pairs(slots)do
  if s.kind=='macro' and s.id==index then slots[slot]={};changed(slot)
  elseif s.kind=='macro' and s.id>index and s.id<=120 then s.id=s.id-1;changed(slot)end
 end
end
function hooksecurefunc(name,fn)
 local original=_G[name]
 _G[name]=function(...)local result={original(...)};fn(...);return unpack(result)end
end
function CreateFrame()
 local frame={};frames[#frames+1]=frame
 function frame:RegisterEvent(event)self[event]=true end
 function frame:SetScript(_,fn)self.handler=fn end
 return frame
end
Enum={UICursorType={Macro=7}}
MAX_ACCOUNT_MACROS=120
C_ActionBar={GetActionText=function(slot)local s=slots[slot];return s and macros[s.id]end}
C_Timer={NewTimer=function(_,fn)local t={Cancel=function(self)self.cancelled=true end};timers[#timers+1]=function()if not t.cancelled then fn()end end;return t end}
assert(loadfile('addon/LycheeTalent/ActionBars.lua'))('LycheeTalent',A)
local B=A.ActionBars
assert(pickups==0,'addon loading must not start cursor work')
local function saveCurrent()
 A.Apply.op={stage='capture-bars'}
 local snapshot=assert(B:Capture(62))
 assert(B:SaveLayout(62,'active',false,snapshot))
 A.Apply.op=nil;settle()
 return snapshot
end
local initial=saveCurrent()
assert(B:SaveIndependent(62,'other',initial))
local completedPickups=pickups
for i=1,500 do display=1000+i;emit('ACTIONBAR_SLOT_CHANGED',i%2==0 and 1 or 0);settle()end
assert(pickups==completedPickups and not cursor,'idle notifications cannot touch cursor')
-- Real drags and swaps are owned entirely by the native action bar.
PickupMacro(2);PlaceAction(1);settle()
assert(cursor.id==1,'displaced macro stays on player cursor')
PlaceAction(2);settle()
assert(cursor.id==121,'character macro survives account macro swap')
ClearCursor();PickupAction(2);PlaceAction(4);settle()
slots[3].id=200;emit('ACTIONBAR_SLOT_CHANGED',3);settle()
assert(B:Get(62,'active',false).slots[1].id==1,'background events do not overwrite profiles')
assert(pickups==completedPickups,'drags do not invoke plugin pickups')
local fresh=saveCurrent()
assert(fresh.slots[1].id==2 and fresh.slots[4].id==1 and not fresh.slots[2].kind,'next switch captures exact macro drag result')
assert(fresh.slots[3].id==200,'next switch captures spell edits')
DeleteMacro(1);settle()
macros[1]='renamed';emit('UPDATE_MACROS');settle()
-- Recreate Lua service state as on reload. Native bars remain authoritative.
assert(loadfile('addon/LycheeTalent/ActionBars.lua'))('LycheeTalent',A);B=A.ActionBars
fresh=saveCurrent()
assert(fresh.slots[1].id==1 and not fresh.slots[4].kind,'capture follows native deletion compaction after reload')
assert(B:Get(62,'other',false).slots[2].id==121,'inactive profile is not changed by native edits')
assert(macros[121]=='same','account deletion does not touch character macros')
completedPickups=pickups
cursor={kind='item',id=123};emit('PLAYER_LOGOUT');settle()
assert(cursor.kind=='item' and cursor.id==123 and pickups==completedPickups,'logout preserves player cursor')
print('PASS '..(deferred and 'deferred' or 'synchronous')..' notifications: no background pickups/saves, exact macro edits captured at switch, reload, inactive profiles and player cursor')
