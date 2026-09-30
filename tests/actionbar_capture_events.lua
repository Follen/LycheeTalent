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
B:Init()
assert(pickups==0,'addon loading must not start cursor work')
A.Apply.op={stage='capture-bars'}
local initial=assert(B:Capture(62));assert(B:SaveLayout(62,'active',false,initial))
if B.Track then B:Track(initial)end
A.Apply.op=nil;settle()
local completedPickups=pickups
for i=1,500 do display=1000+i;emit('ACTIONBAR_SLOT_CHANGED',i%2==0 and 1 or 0);settle()end
assert(pickups==completedPickups,'mouseover/assist refreshes must not mount cursor icons after Applying')
assert(B:Get(62,'active',false).slots[1].id==1,'display spell changes must not replace the macro index')
assert(not cursor,'idle notifications must not change the cursor')
-- Same name and identical body, but a different absolute index.
PickupMacro(2);PlaceAction(1);settle()
assert(B:Get(62,'active',false).slots[1].id==2,'real same-name macro drop saves its exact index')
assert(cursor.id==1,'autosave must preserve the displaced action on the user cursor')
PlaceAction(2);settle()
assert(B:Get(62,'active',false).slots[2].id==1,'a second drop in the same drag chain must not reuse the first ID')
assert(cursor.id==121,'account/character macro swaps preserve absolute indices and cursor contents')
ClearCursor();PlaceAction(1);settle()
assert(B:Get(62,'active',false).slots[1].id==2,'cancelled/empty-cursor drops must not change macro identity')
PickupAction(2);settle()
assert(not B:Get(62,'active',false).slots[2].kind and cursor.id==1,'drag removal saves without stealing the held macro')
PlaceAction(4);settle()
assert(B:Get(62,'active',false).slots[4].id==1,'dragging a macro from an action slot saves its new destination')
slots[3].id=200;emit('ACTIONBAR_SLOT_CHANGED',3);settle()
assert(B:Get(62,'active',false).slots[3].id==200,'ordinary spell edits still autosave')
assert(B:SaveIndependent(62,'other',initial))
DeleteMacro(1);settle()
assert(B:Get(62,'active',false).slots[1].id==1,'active macro slots follow native index compaction')
assert(not B:Get(62,'active',false).slots[4].kind,'deleted macro slot is saved empty')
assert(B:Get(62,'other',false).slots[1].id==1,'deletion must not rewrite other profiles by name/body')
assert(macros[121]=='same','account compaction must not touch character macros')
DeleteMacro(119);settle()
assert(B:Get(62,'active',false).slots[1].id==1,'rejected deletion must not shift cached macro indices')
-- First edit after a reload works before a deferred slot event can run.
emit('PLAYER_ENTERING_WORLD');macros[2]='same';PickupMacro(2);PlaceAction(1);settle()
assert(B:Get(62,'active',false).slots[1].id==2,'first post-reload macro drop must not wait for a slot event')
ClearCursor();PickupMacro(1);rejectDrop=true
emit('CURSOR_CHANGED',false,7,7,99999);PlaceAction(1);settle()
assert(B:Get(62,'active',false).slots[1].id==2 and cursor.id==1,'cursor repaint and rejected placement must not claim an edit')
rejectDrop=false;ClearCursor()
macros[2]='renamed';emit('UPDATE_MACROS');settle()
assert(B:Get(62,'active',false).slots[1].id==2,'renaming/editing a macro keeps its exact index')
readError=true
local ok,why=pcall(emit,'ACTIONBAR_SLOT_CHANGED',3)
assert(not ok and tostring(why):find('injected action read failure',1,true),'API failures remain visible')
readError=false;slots[3].id=300;emit('ACTIONBAR_SLOT_CHANGED',3);settle()
assert(B:Get(62,'active',false).slots[3].id==300,'a failed read does not block subsequent edits')
cursor={kind='item',id=123};emit('PLAYER_LOGOUT');settle()
assert(cursor.kind=='item' and cursor.id==123,'logout does not clear a player cursor')
assert(pickups==completedPickups,'all post-Apply saves are passive')
print('PASS '..(deferred and 'deferred' or 'synchronous')..' events: 500 idle refreshes, exact duplicate macro drag/swap/delete, autosave, untouched cursor, no post-Apply pickups')
