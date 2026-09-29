-- Exercise the production Apply state machine. Unflagging a starter build
-- resets pending changes, so the native load must finish before unflagging.
local function run(mode)
 local starter,selected,active,staged,spec=true,-1,'starter',nil,62
 local frames,timers,callbacks={},{},{}
 local creates,loads,unflags,commits=0,0,0,0
 local now,combat=0,false
 local nodes={[10]={ID=10,name='User config',code='personal',type=1,usesSharedActionBars=true}}
 local A={L={TITLE='Lychee Talent'},Store={character={}},UI={},GetSpec=function()return spec end,
  Message=function(self,key)self.message=key end}
 local char=A.Store.character
 local build={id='chosen',code='desired'}
 local existing=mode~='fresh' and mode~='full' and mode~='create-failure' and mode~='same-name'
 if existing then
  nodes[20]={ID=20,name=A.L.TITLE,code='saved',type=1,usesSharedActionBars=false}
  char.actionBars={version=1,specs={[62]={profiles={},working={id=20,name=A.L.TITLE,spec=62}}}}
 elseif mode=='same-name' then nodes[20]={ID=20,name=A.L.TITLE,code='unowned',type=1,usesSharedActionBars=false}end
 if mode=='remembered' then selected=20 end
 if mode=='same' or mode=='no-change' then active='saved' end
 if mode=='pending' then staged='manual draft' end
 function InCombatLockdown()return combat end
 function GetTime()return now end
 function time()return 1 end
 function GetCursorInfo()end
 function ClearCursor()end
 function GetActionInfo()end
 function CreateFrame()
  local f={};frames[#frames+1]=f
  function f:RegisterEvent(e)self[e]=true end
  function f:UnregisterAllEvents()for k,v in pairs(self)do if v==true then self[k]=nil end end end
  function f:SetScript(_,fn)self.handler=fn end
  return f
 end
 local function emit(event,value)for _,f in ipairs(frames)do if f[event]then f.handler(f,event,value)end end end
 local function later(fn)callbacks[#callbacks+1]=fn end
 C_Timer={NewTimer=function(delay,fn)local t={delay=delay,fn=fn,Cancel=function(self)self.cancelled=true end};timers[#timers+1]=t;return t end}
 Enum={TraitConfigType={Combat=1},LoadConfigResult={Error=0,NoChangesNecessary=1,LoadInProgress=2,Ready=3}}
 C_Traits={GetConfigInfo=function(id)return nodes[id]end,ConfigHasStagedChanges=function()return staged~=nil end,
  RollbackConfig=function()staged=nil;return true end}
 C_ClassTalents={GetActiveConfigID=function()return 1 end,GetLastSelectedSavedConfigID=function()return selected end,
  GetConfigIDsBySpecID=function()local ids={};for id in pairs(nodes)do ids[#ids+1]=id end;return ids end,
  GetStarterBuildActive=function()return starter end,CanEditTalents=function()return true end,
  CanCreateNewConfig=function()return not existing and mode~='full' end,
  IsConfigPopulated=function()return true end,
  UpdateLastSelectedSavedConfigID=function(_,id)selected=id end,
  SetUsesSharedActionBars=function(id,value)nodes[id].usesSharedActionBars=value end,
  DeleteConfig=function()error('must not delete player configs')end,
  ImportLoadout=function(_,entries,name)
   creates=creates+1
   if mode=='create-failure' then return false end
   nodes[30]={ID=30,name=name,code=entries.code,type=1,usesSharedActionBars=true}
   later(function()emit('TRAIT_CONFIG_CREATED',nodes[30])end)
   return true
  end,
  LoadConfig=function(id,auto)
   assert(auto);loads=loads+1
   if mode=='load-failure' then return 0 end
   if mode=='ready' then staged=nodes[id].code;return 3 end
   if mode=='no-change' then assert(active==nodes[id].code);return 1 end
   later(function()active=nodes[id].code;staged=nil;if mode=='auto-unflag' then starter=false end;emit('TRAIT_CONFIG_UPDATED',1)end)
   return 2
  end,
  SetStarterBuildActive=function(value)
   assert(value==false);unflags=unflags+1
   assert(loads==1 and not staged and nodes[selected] and active==nodes[selected].code,'must finish and select native load before unflagging')
   if mode=='unflag-failure' then return 0 end
   if mode=='timeout' then return 2 end
   if mode=='sync' then starter=false;return 1 end
   later(function()
    if mode=='unflag-event-failure' then emit('STARTER_BUILD_ACTIVATION_FAILED');return end
    if mode=='combat' then combat=true;emit('PLAYER_REGEN_DISABLED');return end
    if mode=='spec-change' then spec=63;emit('ACTIVE_PLAYER_SPECIALIZATION_CHANGED');return end
    starter=false;staged=nil;emit('TRAIT_CONFIG_UPDATED',1)
   end)
   return 2
  end,
  CommitConfig=function(id)
   commits=commits+1;local code=staged
   later(function()active=code;nodes[id].code=code;staged=nil;emit('TRAIT_CONFIG_UPDATED',1)end)
   return true
  end,
  SaveConfig=function(id)assert(not starter);nodes[id].code=active;return true end}
 A.Catalog={Find=function()return build end}
 A.Talents={Code=function(_,b)return b.code end,Validate=function(_,code)return code,62 end,
  Entries=function(_,code)return {code=code}end,Frame=function()return {}end,
  ReadEntries=function(_,id)return {code=id==1 and (staged or active)or nodes[id].code}end,
  Export=function(_,draft)return draft and (staged or active)or active end,
  Matches=function(_,id,entries)return (id==1 and (staged or active)or nodes[id].code)==entries.code end,
  StageEntries=function(_,_,entries)assert(not starter,'do not stage while the starter flag is active');staged=entries.code;return true end}
 assert(loadfile('addon/LycheeTalent/ActionBars.lua'))('LycheeTalent',A)
 assert(loadfile('addon/LycheeTalent/Apply.lua'))('LycheeTalent',A)
 -- A remembered native config cannot identify a plugin build while Starter is active.
 if mode=='remembered' then
  active='desired';nodes[20].code=active
  char.applied={id=build.id,code=build.code,spec=62,config=20,entries={code=active}}
  assert(not A.Apply:CurrentBuildID(),'starter mode must not overwrite a previous managed profile')
 end
 local ok,why=A.Apply:Start(build,false)
 if mode=='pending' then
  assert(not ok and why=='PENDING' and staged=='manual draft' and creates==0 and loads==0 and unflags==0,'keep manual draft and request existing confirmation')
  return
 end
 assert(ok,'starter build must enter normal creation/loading: '..tostring(why))
 for _=1,100 do
  local pending=callbacks;callbacks={};for _,fn in ipairs(pending)do fn()end
  local queued=timers;timers={};local progressed=#pending>0
  for _,t in ipairs(queued)do
   if not t.cancelled then
    if t.delay<=1 then now=now+t.delay;t.fn();progressed=true else timers[#timers+1]=t end
   end
  end
  if not progressed then break end
 end
 if mode=='timeout' then assert(A.Apply.op);A.Apply.timer.fn()end
 local errors={full='NATIVE_LIMIT',['create-failure']='APPLY_FAILED',['load-failure']='APPLY_FAILED',
  ['unflag-failure']='STARTER_FAILED',['unflag-event-failure']='STARTER_FAILED',timeout='APPLY_TIMEOUT',combat='APPLY_COMBAT',['spec-change']='APPLY_SPEC_CHANGED'}
 if errors[mode] then
  assert(not A.Apply.op and A.message==errors[mode],mode..': '..tostring(A.message))
  assert(starter,'unsuccessful handoff must not clear Starter early')
  if mode=='full' or mode=='create-failure' or mode=='load-failure' then assert(unflags==0)end
 else
  assert(not A.Apply.op and A.message=='APPLY_SUCCESS' and not starter and active=='desired',mode..': '..tostring(A.message))
  assert(creates==(existing and 0 or 1) and loads==1,'create at most once; always load out of Starter')
  assert(unflags==(mode=='auto-unflag' and 0 or 1),'unflag exactly once when needed')
  assert(nodes[selected].name==A.L.TITLE and not nodes[selected].usesSharedActionBars)
 end
 assert(nodes[10].name=='User config' and nodes[10].code=='personal','keep user configs')
 if mode=='same-name' then assert(nodes[20].code=='unowned','do not adopt a same-name unowned config')end
 print('PASS starter handoff: '..mode)
end
for _,mode in ipairs({'fresh','existing','remembered','same','no-change','ready','sync','auto-unflag','same-name',
 'full','create-failure','load-failure','unflag-failure','unflag-event-failure','timeout','combat','spec-change','pending'})do run(mode)end
