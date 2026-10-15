local T=assert(loadfile('tests/macro_runtime.lua'))()(arg[1]=='deferred')
local A,B=T.A,T.B
T.spec=261
local known={[53]=true,[196819]=true}
C_SpellBook={IsSpellKnown=function(id)return known[id]==true end}
C_Spell.GetBaseSpell=function(id)return id end
C_Spell.GetSpellInfo=function(id)return {spellID=id} end
C_Spell.PickupSpell=function(id)
    if known[id] then T.cursor={kind='spell',id=id,sub='spell'} end
end
local target=assert(B:Capture(261))
target.slots[51]={kind='spell',id=53,sub='spell'}
target.slots[53]={kind='spell',id=385627,sub='spell'}
local ok,why=B:Restore(target)
assert(ok,'an inactive saved spell must not abort the available actions: '..tostring(why))
assert(T.slots[51].id==53,'learned skill restored')
assert(B.verified.deferredSpells[53].id==385627,'inactive skill remains in the saved layout')
assert(not T.slots[53] or not T.slots[53].kind,'no nonexistent action placed')
assert(B:SaveLayout(261,'shared',true,B.verified))
B:Spec(261).applied={id='shared',spec=261,shared=true}
B:Init();T.settle()
T.emit('ACTIONBAR_SLOT_CHANGED',0);T.settle()
local shared=assert(B:Get(261,'shared',true))
assert(shared.deferredSpells[53].id==385627,'passive events retain the inactive skill')
assert(B:Capture(261).deferredSpells[53].id==385627,'switching away retains the inactive skill')
assert(B:SaveIndependent(261,'independent',shared))
T.slots[53]={kind='spell',id=196819,sub='spell'}
T.emit('ACTIONBAR_SLOT_CHANGED',53);T.settle()
assert(not B:Get(261,'shared',true).deferredSpells,'manual replacement cancels the retained skill in this layout')
assert(B:Get(261,'independent',false).deferredSpells[53].id==385627,'other layouts are unchanged')
T.activate('independent',false,shared)
assert(T.slots[53].id==196819 and B:Get(261,'independent',false).deferredSpells[53].id==385627,
    'unavailable target retains the current action and its saved destination')
T.frames={}
assert(loadfile('addon/LycheeTalent/ActionBars.lua'))('LycheeTalent',A);B=A.ActionBars;T.B=B
B:Init();T.emit('PLAYER_ENTERING_WORLD');T.settle()
assert(B:Get(261,'independent',false).deferredSpells[53].id==385627,'reload retains the inactive skill')
known[385627]=true
T.activate('independent',false,B:Get(261,'independent',false))
assert(T.slots[53].id==385627 and not B.verified.deferredSpells,'learning the skill restores its original slot')
local learned=assert(B:Capture(261));learned.slots[54]={kind='spell',id=777,sub='spell'}
known[777]=true
local pickup=C_Spell.PickupSpell
C_Spell.PickupSpell=function(id)if id~=777 then pickup(id)end end
local placements=T.placements
local restored,reason,detail=B:Restore(learned)
assert(not restored and reason=='BARS_UNAVAILABLE' and detail.slot==54 and T.placements==placements,
    'a learned spell pickup failure remains a real error with the exact slot')
C_Item.PickupItem=function()end
learned.slots[54]={kind='item',id=888}
restored,reason,detail=B:Restore(learned)
assert(not restored and reason=='BARS_UNAVAILABLE' and detail.slot==54,'missing items are not classified as inactive talents')
assert(not T.cursor,'all pickups leave the cursor empty')
print('PASS inactive spells: restore, passive saves, manual edits, independent layouts, reload, relearning and real failures')
