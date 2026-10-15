local T=assert(loadfile('tests/macro_runtime.lua'))()(false)
local A,B=T.A,T.B
T.native[1]={name='same',icon=134400,body='/cast Alpha'}
T.native[2]={name='same',icon=134400,body='/cast Beta'}
T.native[121]={name='same',icon=134400,body='/cast Alpha'}
T.slots[1]={kind='macro',id=1};T.slots[2]={kind='macro',id=2};T.slots[3]={kind='macro',id=121}
local snapshot=assert(B:Capture(62))
assert(snapshot.version==2 and T.body(snapshot,1)=='/cast Alpha' and T.body(snapshot,2)=='/cast Beta')
assert(snapshot.bindings[snapshot.slots[3].id].index==121,'native binding remains a hint, with content stored separately')
snapshot.slots[1],snapshot.slots[2]=snapshot.slots[2],snapshot.slots[1]
assert(B:Restore(snapshot) and T.slots[1].id==2 and T.slots[2].id==1 and T.slots[3].id==121)
assert(T.writes==0,'matching user macros do not need edits or pool slots')
local beforeCopies=T.copies
T.cursor={kind='item',id=123}
local ok,why=B:Capture(62)
assert(not ok and why=='BARS_CURSOR' and T.cursor.id==123 and T.copies==beforeCopies)
T.cursor=nil;T.combat=true
assert(not B:Restore(snapshot) and T.writes==0);T.combat=false
-- Reused numeric positions must not replace the saved macro text.
T.native[1]={name='replacement',icon=1,body='/say Replacement'}
T.native[2]={name='same',icon=1,body='/say Also changed'}
T.native[121]={name='same',icon=1,body='/say Character macro'}
assert(B:Restore(snapshot))
assert(T.native[T.slots[1].id].body=='/cast Beta' and T.native[T.slots[2].id].body=='/cast Alpha')
assert(T.native[1].body=='/say Replacement' and T.native[2].body=='/say Also changed' and T.native[121].body=='/say Character macro')
assert(#A.Store.character.macroPool==2,'duplicate macro bodies share one execution slot')
local poolSize=#A.Store.character.macroPool
local alternate=A.Macros.Copy(snapshot)
alternate.macros[alternate.slots[1].id].body='/cast Gamma'
assert(B:Restore(alternate) and #A.Store.character.macroPool==poolSize,'switches reuse the pool')
assert(T.native[T.slots[1].id].body=='/cast Gamma')
assert(B:Restore(snapshot) and T.native[T.slots[1].id].body=='/cast Beta')
-- Macro edits and action placement form one recoverable operation.
local current=T.native[T.slots[1].id].body
alternate.slots[4]={kind='item',id=999};T.failPlace=true
local restored,reason,detail=B:Restore(alternate)
assert(not restored and reason=='BARS_RESTORE' and detail.rolledBack)
assert(T.native[T.slots[1].id].body==current and (not T.slots[4] or not T.slots[4].kind) and not T.cursor,'rollback restores both macro text and action slots')
T.failEdit=true
assert(not B:Restore(alternate) and T.native[T.slots[1].id].body==current,'failed native edit retains prior text')
local crowded=A.Macros.Copy(snapshot)
crowded.macros.extra={name='Extra',icon=1,body='/cast Extra'};crowded.slots[10]={kind='macro',id='extra'}
Constants.MacroConsts.MAX_CHARACTER_MACROS=3
local writes=T.writes
ok,why=B:Restore(crowded)
assert(not ok and why=='BARS_MACRO_CAPACITY' and T.writes==writes,'capacity fails before writing')
Constants.MacroConsts.MAX_CHARACTER_MACROS=30
-- Slot 61 exposes a plain macro index, so it never needs a copied pickup.
T.slots[61]={kind='macro',id=121,plain=true}
local pickup=PickupAction
PickupAction=function(slot,keep)assert(slot~=61 or not keep,'plain macros need no copy');return pickup(slot,keep)end
local direct=assert(B:Capture(62));assert(T.body(direct,61)=='/say Character macro')
direct.slots[61]={kind='unreadableMacro',id=61}
assert(B:Restore(direct) and T.body(B.verified,61)=='/say Character macro')
local legacy={version=1,spec=62,slots={}}
for i=1,180 do legacy.slots[i]={}end
legacy.slots[1]={kind='macro',id=1}
assert(B:SaveIndependent(62,'legacy',legacy))
assert(T.body(B:Get(62,'legacy',false),1)=='/say Replacement','legacy imports text still available at migration')
T.native[1].body='/say Later'
assert(T.body(B:Get(62,'legacy',false),1)=='/say Replacement','converted legacy layouts freeze their own content')
T.native[4]={name='Empty macro',icon=134400}
assert(A.Macros:Read(4).body=='','native macros without a body are saved as empty text')
local getMacro=GetMacroInfo
GetMacroInfo=function(index)local name,icon,body=getMacro(index);return name,icon and 999999,body end
assert(A.Macros:Read(4).icon==134400,'store the selected icon, not the dynamic tooltip icon')
print('PASS macro snapshots: raw text, duplicate names, replacement IDs, reusable pool, capacity, rollback, plain macros and legacy import')
