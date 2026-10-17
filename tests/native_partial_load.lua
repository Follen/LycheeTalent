-- A native Ready load can omit a requested rank in both its saved config and
-- active draft. Comparing those two snapshots alone must not submit 33/34.
-- The reported Devourer node is Void Purge (110174 / entry 136699).
local function run(mode)
 local full=mode=='fresh' or mode=='existing'
 local node={ID=110174,entryIDs={136699},type=0,maxRanks=1,posY=6900,
  activeEntry={entryID=136699},ranksPurchased=mode=='complete' and 1 or 0,
  activeRank=mode=='complete' and 1 or 0,isAvailable=true,isVisible=true}
 local saved=node.ranksPurchased
 local commits,resets,rollbacks,creates=0,0,0,0
 local staged=not full
 local A={GetSpec=function()return 1480 end,Store={character={recovery={}}},UI={},L={TITLE='Lychee Talent'},
  Message=function(self,key)self.message=key end}
 InCombatLockdown=function()return false end
 time=function()return 1 end;GetTime=function()return 1 end
 Enum={TraitNodeType={Selection=2,SubTreeSelection=3},LoadConfigResult={Error=0,Ready=3}}
 Enum.TraitConfigType={Combat=1}
 local configs={[3]={ID=3,name='User config',type=1,usesSharedActionBars=false}}
 if mode=='existing' then configs[2]={ID=2,name=A.L.TITLE,type=1,usesSharedActionBars=false}end
 C_Traits={
  GetConfigInfo=function(id)return configs[id]end,
  GetNodeInfo=function()return node end,
  ConfigHasStagedChanges=function()return staged end,
  ResetTree=function()
   resets=resets+1;node.ranksPurchased=0;node.activeRank=0;return true
  end,
  CanPurchaseRank=function()return mode~='blocked' and node.ranksPurchased<1 end,
  PurchaseRank=function()node.ranksPurchased=1;node.activeRank=1;return true end,
  RollbackConfig=function()
   rollbacks=rollbacks+1;node.ranksPurchased=saved;node.activeRank=saved;staged=false;return true
  end,
 }
 local selected=3
 C_ClassTalents={GetTraitTreeForSpec=function()return 854 end,GetActiveConfigID=function()return 1 end,
  GetStarterBuildActive=function()return mode=='starter' end,
  LoadConfig=function()staged=true;return Enum.LoadConfigResult.Ready end,
  CommitConfig=function()
   commits=commits+1
   if mode~='starter' then
    assert(node.ranksPurchased==1,'native commit still has 1 unspent Devourer spec point (33/34)')
   end
   if mode=='commit-failure' then return false end
   saved=node.ranksPurchased;staged=false;return true
  end,
  UpdateLastSelectedSavedConfigID=function(_,id)selected=id end,
  GetLastSelectedSavedConfigID=function()return selected end,
  GetConfigIDsBySpecID=function()return configs[2] and {2,3} or {3}end,
  CanEditTalents=function()return true end,CanCreateNewConfig=function()return true end,
  IsConfigPopulated=function()return true end,
  ImportLoadout=function(_,_,name)
   creates=creates+1;configs[2]={ID=2,name=name,type=1,usesSharedActionBars=false}
   A.Apply:OnEvent('TRAIT_CONFIG_CREATED',configs[2]);return true
  end,
 }
 assert(loadfile('addon/LycheeTalent/Talents.lua'))('LycheeTalent',A)
 -- Keep the native snapshots at this seam; exercise production StageEntries.
 A.Talents.ReadEntries=function(_,id)
  return {{nodeID=110174,selectionEntryID=136699,ranksPurchased=id==1 and node.ranksPurchased or saved}}
 end
 A.Talents.Matches=function(self,id,entries)
  return self:ReadEntries(id)[1].ranksPurchased==(entries[1].ranksPurchased or 0)
 end
 assert(loadfile('addon/LycheeTalent/Apply.lua'))('LycheeTalent',A)
 local target={{nodeID=110174,selectionEntryID=136699,ranksPurchased=1}}
 local timers={}
 C_Timer={NewTimer=function(delay,fn)
  local timer={delay=delay,fn=fn,Cancel=function(self)self.cancelled=true end}
  timers[#timers+1]=timer;return timer
 end}
 if full then
  -- Run both initial creation and an already-owned working config through
  -- Start, native Ready, production staging, native commit and completion.
  local state={default={}}
  if mode=='existing' then state.working={id=2,name=A.L.TITLE,spec=1480}end
  A.ActionBars={Spec=function()return state end,Working=function()return state.working end,
   Capture=function()return {}end,Get=function()return {}end,Plan=function()return {}end,
   Restore=function()return true end,SaveLayout=function()return true end}
  A.Talents.Code=function()return 'target' end
  A.Talents.Validate=function()return 'target',1480 end
  A.Talents.Entries=function()return target end
  A.Talents.Export=function()return 'original' end
  A.Talents.Frame=function()return {}end
  GetCursorInfo=function()end
  CreateFrame=function()return {SetScript=function()end,RegisterEvent=function()end,UnregisterAllEvents=function()end}end
  assert(A.Apply:Start({id='devourer',code='target'},true))
  for _=1,20 do
   local pending=timers;timers={}
   for _,timer in ipairs(pending)do if not timer.cancelled and timer.delay<25 then timer.fn()end end
   if not A.Apply.op then break end
  end
  assert(not A.Apply.op and A.message=='APPLY_SUCCESS',tostring(A.message))
  assert(creates==(mode=='fresh' and 1 or 0) and state.applied and state.applied.config==2,
   'native creation/reuse must complete under the same requested build')
 else
  A.Apply.op={spec=1480,target=2,entries=target}
  A.Apply:LoadNative(2,function()end)
 end
 if mode=='commit-failure' then
  assert(commits==1 and resets==1 and rollbacks==1 and A.message=='COMMIT_FAILED',
   'a rejected Ready commit must roll back its draft')
 elseif mode=='blocked' then
  assert(commits==0 and rollbacks==1 and A.message=='STAGED_MISMATCH',
   'an unpurchasable requested rank must roll back before native commit')
 else
  assert(commits==1 and resets==((mode=='partial' or full) and 1 or 0),
   'only incomplete Ready loads need target staging; Starter handoff keeps its existing order')
 end
 print('PASS native Ready load: '..mode)
end
for _,mode in ipairs({'partial','complete','blocked','commit-failure','starter','fresh','existing'})do run(mode)end
