-- Replay the live failure: version 1 layouts already contain macro text, but
-- their recorded account/character indices have since disappeared or changed.
local T=assert(loadfile('tests/macro_runtime.lua'))()(false)
local A,B=T.A,T.B
assert(loadfile('addon/LycheeTalent/Migration.lua'))('LycheeTalent',A)
assert(loadfile('addon/LycheeTalent/Storage.lua'))('LycheeTalent',A)
T.native[1]={name='Replacement',icon=10,body='/say Unrelated current macro'}
local legacy={version=1,spec=62,slots={}}
for slot=1,180 do legacy.slots[slot]={}end
legacy.slots[26]={kind='macro',id=40,sub='MOUNT',name='Saved mount',body='/cast Saved mount',character=false}
legacy.slots[61]={kind='macro',id=1,sub='spell',name='Saved heal',body='/cast Saved heal',character=false}
local oldAccount={version=1,nextID=0,builds={{id=4,specID=62,name='Saved build',code='talents'}},remindersEnabled=true}
local oldCharacter={modes={['4']=false},applied={id=4,spec=62,shared=false},raidDifficulty=5,
 actionBars={version=1,specs={[62]={profiles={},default=legacy}}},recovery={spec=62,bars=T.copy(legacy)}}
LycheeTalentDB,LycheeTalentCharacterDB=oldAccount,oldCharacter
A.Store:Init()
assert(not A.Store.readonly)
local db,char=A.Store.db,A.Store.character
assert(db.schema=='Lychee.Talent.Schema.V1:' and char.schema==db.schema)
assert(db~=oldAccount and char~=oldCharacter,'replace the legacy saved roots only after complete conversion')
assert(db.version==nil and char.modes==nil and char.applied==nil,'remove legacy fields')
assert(db.nextID==4 and db.builds[1].name=='Saved build' and db.remindersEnabled and char.raidDifficulty==5)
assert(B:Spec(62).applied.id==4 and not B:IsShared(62,4) and B:IsShared(62,'new'))
assert(char.recovery.bars.version==2,'recovery layouts migrate in the same pass')
local snapshot,why=B:Get(62,nil,true)
assert(snapshot,'legacy raw macro text must survive missing native indices: '..tostring(why))
assert(T.body(snapshot,26)=='/cast Saved mount','do not require deleted native index 40')
assert(T.body(snapshot,61)=='/cast Saved heal','do not replace saved content with the current occupant of index 1')
assert(B:Restore(snapshot))
assert(T.native[T.slots[26].id].body=='/cast Saved mount' and T.native[T.slots[61].id].body=='/cast Saved heal')
assert(T.native[1].body=='/say Unrelated current macro','do not edit the unrelated replacement')
local read=GetMacroInfo
GetMacroInfo=function()error('already migrated data must not read native macros again')end
A.Store:Init()
assert(A.Store.db==db and A.Store.character==char,'marked roots skip migration on subsequent loads')
GetMacroInfo=read
local indexOnly=T.copy(legacy);indexOnly.slots[26]={kind='macro',id=40}
local incomplete={actionBars={version=1,specs={[62]={profiles={},default=indexOnly}}}}
LycheeTalentDB,LycheeTalentCharacterDB=oldAccount,incomplete
A.Store:Init()
assert(not A.Store.readonly and B:Get(62,nil,true).slots[26].kind=='unreadableMacro',
 'deleted index-only macros migrate as preserved slots rather than blocking all saved builds')
local future={schema='Lychee.Talent.Schema.V2:'}
LycheeTalentDB,LycheeTalentCharacterDB=oldAccount,future
A.Store:Init()
assert(A.Store.readonly and LycheeTalentDB==oldAccount and LycheeTalentCharacterDB==future,
 'an unsupported schema must not delete either original root')
print('PASS one-time schema migration: raw macro text, deleted/reused IDs, per-spec preferences, cleanup, idempotence and atomic failure')
