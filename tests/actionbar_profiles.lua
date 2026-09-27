local A={Store={character={}}}
assert(loadfile('addon/LycheeTalent/ActionBars.lua'))('LycheeTalent',A)
local B=A.ActionBars
assert(not B:Spec(0) and not B:Spec(-1),'uninitialized specialization creates no profile')
local function snapshot(spec,id)
 local slots={};for i=1,180 do slots[i]={} end
 slots[1]={kind='spell',id=id}
 return {version=1,spec=spec,slots=slots}
end
assert(B:SaveIndependent(65,'independent',snapshot(65,99)))
assert(not B:Get(65,'independent',true),'missing shared default must never fall back to independent')
local first=snapshot(62,100)
assert(B:SeedDefault(62,first,'first-use'))
first.slots[1].id=999
assert(B:Get(62,nil,true).slots[1].id==100,'initial snapshot must not alias caller')
assert(B:SaveIndependent(62,'dungeon',snapshot(62,200)))
assert(B:SaveIndependent(62,'dungeon',snapshot(62,201)))
assert(B:Get(62,'dungeon',false).slots[1].id==201,'independent edits are retained')
assert(B:Get(62,'dungeon',true).slots[1].id==100,'independent to shared preserves default')
assert(B:SeedDefault(62,snapshot(62,300),'native-shared'))
assert(B:Get(62,nil,true).slots[1].id==100,'upgrade retains preexisting default')
assert(B:SeedDefault(63,snapshot(63,400),'first-use'))
assert(not B:SaveIndependent(63,'dungeon',snapshot(62,500)),'cross-spec snapshots rejected')
assert(B:Get(63,nil,true).slots[1].id==400,'each spec has its own default')
local copy=B:Get(62,'dungeon',false);copy.slots[1].id=999
assert(B:Get(62,'dungeon',false).slots[1].id==201,'reads cannot mutate stored layout')
local bad=snapshot(64,1);bad.slots[180]=nil
assert(not B:SaveIndependent(64,'bad',bad),'truncated snapshots rejected')
B.profileLimit=1
assert(not B:SaveIndependent(62,'another',snapshot(62,10)),'bounded profile count')
A.Store.character.actionBars.version=2
assert(not B:SeedDefault(65,snapshot(65,800),'first-use'),'future schema is preserved')
print('PASS action-bar profiles: defaults, independent isolation, spec isolation, ownership copies, bounds')

