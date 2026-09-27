local frames,timers,shown,applied,loads,localizations={}, {},0,0,0,0
local catalogReady=false
local combat,spec,kind,instance,raidDifficulty=false,71,'none',0,15
local x,y,map,positionAvailable=.4,.4,20,true
local markers={{encounterID=88,mapX=.4,mapY=.4},{encounterID=99,mapX=.8,mapY=.8}}
local secret={}
function issecretvalue(v)return v==secret end
function InCombatLockdown()return combat end
function GetInstanceInfo()return 'Instance',kind,kind=='raid' and raidDifficulty or 0,'',5,0,false,instance end
function CreateFrame()
 local f={events={}};frames[#frames+1]=f
 function f:RegisterEvent(e)self.events[e]=true end
 function f:UnregisterEvent(e)self.events[e]=nil end
 function f:UnregisterAllEvents()self.events={}end
 function f:SetScript(_,fn)self.handler=fn end
 return f
end
C_Timer={NewTimer=function(_,fn)local t={fn=fn,Cancel=function(self)self.cancelled=true end};timers[#timers+1]=t;return t end}
C_Map={GetBestMapForUnit=function()assert(not combat,'position read in combat');return map end,
 GetPlayerMapPosition=function()if positionAvailable then return {GetXY=function()return x,y end}end end,
 GetMapWorldSize=function()return 1000,1000 end}
C_EncounterJournal={GetEncountersOnMap=function()return markers end}
local scenes={{id='11',scene='mythic',mapID=1001,label='Dungeon'},{id='222',scene='raid',journalID=88,label='Boss'},{id='333',scene='raid',journalID=99,label='Other'}}
local byID={};for _,s in ipairs(scenes)do byID[s.id]=s end
local b={id=1,name='Personal',source='user',specID=71,contexts={['11']=true,['222']=true}}
local current
local builtin={id='wcl:dungeon',name='WCL dungeon',source='builtin',specIndex=1,scenarioID='11',scene='mythic',kind='highest'}
C_SpecializationInfo={GetSpecialization=function()return spec==71 and 1 or 2 end}
local A={Scenarios=scenes,L={},GetSpec=function()return spec end,
 Catalog={scenarios=byID,builds={},Load=function()loads=loads+1;catalogReady=true end,Localize=function()localizations=localizations+1 end},
 Store={db={remindersEnabled=false},character={modes={}},builds={b},Find=function(_,id)if id==1 then return b end end},
 Apply={CurrentBuildID=function()if type(current)=='string' and not catalogReady then return nil end;return current end,
   Start=function(_,build)assert(build==b);applied=applied+1;current=b.id;return true end},
 UI={ShowReminder=function(self,p)shown=shown+1;self.last=p;self.reminder={Hide=function()end}end}}
assert(loadfile('addon/LycheeTalent/Reminders.lua'))('LycheeTalent',A)
local R=A.Reminders
local function event(name,...)
 for _,f in ipairs(frames)do if f.events[name]then f.handler(f,name,...)end end
 local pending=timers;timers={};for _,t in ipairs(pending)do if not t.cancelled then t.fn()end end
end
R:RefreshSettings();assert(#frames==0 and localizations==0,'disabled reminders create no frames/events or catalog work')
A.Store.db.remindersEnabled=true;b.remind=true;R:RefreshSettings();assert(#frames==1 and not frames[1].events.PLAYER_STOPPED_MOVING)
assert(loads==0,'enabling reminders outside an instance does not load class data')
kind,instance='party',1001;event('ZONE_CHANGED_NEW_AREA')
assert(shown==1 and R.visible.id=='11' and applied==0,'dungeon entry prompts without applying')
assert(loads==1,'entering a supported instance loads recommendations on demand')
event('ZONE_CHANGED');assert(shown==1,'same visit does not repeat')
assert(R:Apply(1) and applied==1 and not R.visible,'explicit choice applies via shared engine')
kind='none';event('ZONE_CHANGED_NEW_AREA');kind='party';event('ZONE_CHANGED_NEW_AREA')
assert(shown==1,'already applied build is not prompted')
current=nil;spec=72;kind='none';event('ZONE_CHANGED_NEW_AREA');kind='party';event('ZONE_CHANGED_NEW_AREA')
assert(shown==1,'other specialization does not receive this build')
spec=71;kind='raid';instance=2002;event('ZONE_CHANGED_NEW_AREA')
assert(shown==2 and R.visible.id=='222' and frames[1].events.PLAYER_STOPPED_MOVING,'raid marker proximity uses event-driven check')
combat=true;event('PLAYER_REGEN_DISABLED');assert(not R.visible and not frames[1].events.PLAYER_STOPPED_MOVING)
combat=false;event('PLAYER_REGEN_ENABLED');assert(shown==3,'combat defers unhandled prompt')
combat=true;event('PLAYER_REGEN_DISABLED');event('ENCOUNTER_END',222,'Boss',0,20,1)
combat=false;event('PLAYER_REGEN_ENABLED');assert(shown==3,'completed boss does not prompt after combat')
kind='none';event('ZONE_CHANGED_NEW_AREA');kind='raid';positionAvailable=false;event('ZONE_CHANGED_NEW_AREA')
assert(shown==3,'missing map position does not guess')
positionAvailable=true;x=secret;event('PLAYER_STOPPED_MOVING');assert(shown==3,'secret coordinate is not inspected')
x=.4;markers[2].mapX=.4;markers[2].mapY=.4;event('PLAYER_STOPPED_MOVING');assert(shown==3,'ambiguous boss markers do not guess')
markers[2].mapX=.8;markers[2].mapY=.8;event('PLAYER_STOPPED_MOVING');assert(shown==4)
instance=1002;kind='party';local ok,why=R:Apply(1);assert(not ok and why=='REMINDER_CHANGED' and applied==1,'stale prompt cannot apply')
A.Store.db.remindersEnabled=false;b.remind=false;R:RefreshSettings();assert(not next(frames[1].events) and not R.visible and not R.timer,'disabled state releases every event and timer')
A.Store.db.remindersEnabled=true;b.remind=true;R:RefreshSettings();assert(#frames==1,'re-enable reuses one event frame')
print('PASS reminders: opt-in zero listeners, instance/boss matching, explicit apply, dedup, spec/combat/secret guards, stale prompt and disable cleanup')

-- User report: a built-in from another dungeon must prompt on entry, with no personal association.
b.remind=false;A.Catalog.builds={builtin};current='wcl:other-dungeon'
kind='none';R:Check();kind='party';instance=1001
local before=shown;R:RefreshSettings()
assert(shown==before+1 and R.visible.builds[1]==builtin,'built-in WCL dungeon entry must prompt without personal associations')
A.Store.db.remindersEnabled=false;R:RefreshSettings()
assert(not R.visible and not next(frames[1].events),'global off suppresses built-in and personal reminders')
print('PASS built-in arrival and global switch')

A.Store.db.remindersEnabled=true;A.Store.builds={};current=nil;kind='none';R:Check();kind='party';instance=1001;R:RefreshSettings()
A.Apply.Start=function(_,build)assert(build==builtin);current=build.id;return true end
assert(R:Apply(builtin.id) and current==builtin.id,'builtin reminder applies exact catalog build')
kind='none';R:Check();kind='party';local total=shown;R:Check();assert(shown==total,'current builtin does not prompt')
-- After login the applied ID cannot resolve until the class catalog loads.
kind='none';R:Check();catalogReady=false;kind='party';total=shown;R:Check()
assert(shown==total and catalogReady,'already-applied builtin is recognized on first instance check after login')
local raid={id='wcl:raid',name='Raid',source='builtin',specIndex=1,scenarioID='222',scene='raid',difficulty=4,kind='ranked'}
A.Catalog.builds={raid};kind='raid';instance=2002;R:Check();assert(R.visible and R.visible.builds[1]==raid,'raid default WCL matches boss')
kind='none';R:Check();kind='raid';raidDifficulty=14;R:Check()
assert(not R.visible,'normal raid does not borrow a heroic WCL recommendation')
A.Store.builds={b};b.remind=true;R:Check()
assert(R.visible and R.visible.builds[1]==b,'personal boss association remains available on normal raid')
A.Store.builds={}
local mythicRaid={id='wcl:raid-mythic',source='builtin',specIndex=1,scenarioID='222',scene='raid',difficulty=5,kind='ranked'}
A.Catalog.builds={raid,mythicRaid};kind='none';R:Check();kind='raid';raidDifficulty=16;R:Check()
assert(R.visible and R.visible.builds[1]==mythicRaid,'mythic raid selects its exact WCL difficulty')
kind='none';R:Check();kind='raid';raidDifficulty=secret;R:Check()
assert(not R.visible,'secret raid difficulty is not inspected or mapped to heroic')
raidDifficulty=15

-- The default list hides the popular alternative; it must not become a reminder default.
local popular={id='wcl:popular',source='builtin',specIndex=1,scenarioID='11',scene='mythic',kind='popular'}
A.Catalog.builds={popular};kind='none';R:Check();kind='party';instance=1001;current=nil
local beforePopular=shown;R:Check()
assert(shown==beforePopular and not R.visible,'hidden popular alternative is not offered as default')
