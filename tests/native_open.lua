-- Exercise the pinned native OnShow selection path with production OpenNative.
local A={GetSpec=function()return 62 end}
InCombatLockdown=function()return false end
local selected,loads,opened=nil,0,0
local f={variablesLoaded=true}
f.IsShown=function()return true end
f.IsInspecting=function()return false end
f.GetIsStarterBuildActive=function()return false end
f.LoadSystem={GetSelectionID=function()return selected end,
 IsSelectionIDValid=function(_,id)return id==10 end,
 SetSelectionID=function(_,id)selected=id end}
f.LoadConfigInternal=function()loads=loads+1 end
ClassTalentsFrameMixin={}
local src=assert(io.open('analyze/Blizzard/Frame.lua')):read('*a')
local function native(name,nextName)
 local start=assert(src:find('function ClassTalentsFrameMixin:'..name..'(',1,true))
 local finish=assert(src:find('function ClassTalentsFrameMixin:'..nextName..'(',start+1,true))
 assert(loadstring(src:sub(start,finish-1)))()
 f[name]=ClassTalentsFrameMixin[name]
end
native('CheckSetSelectedConfigID','TrySetSeenPurchasableClassCapstone')
native('SetSelectedSavedConfigID','RefreshConfigID')
Constants={TraitConsts={STARTER_BUILD_TRAIT_CONFIG_ID=-1}}
PlayerUtil={GetCurrentSpecID=function()return 62 end}
C_ClassTalents={GetLastSelectedSavedConfigID=function()return 10 end,GetStarterBuildActive=function()return false end}
PlayerSpellsFrame={TalentsFrame=f}
PlayerSpellsUtil={OpenToClassTalentsTab=function()opened=opened+1;f:CheckSetSelectedConfigID()end}
assert(loadfile('addon/LycheeTalent/Talents.lua'))('LycheeTalent',A)
assert(A.Talents:OpenNative())
assert(opened==1 and loads==0,'opening the addon must not stage the last saved loadout')
assert(selected==10,'native selection still identifies the saved loadout')
assert(A.Talents:OpenNative());assert(loads==0)
print('PASS native first-open selection: no talent load')
