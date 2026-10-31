-- Stage live ranks without rereading full native metadata per sort comparison.
local A={GetSpec=function()return 62 end}
local entries,nodes,purchases={}, {}, {}
for id=1,80 do
 local y=id%9
 nodes[id]={ID=id,posY=y,ranksPurchased=0,type=1,isAvailable=true,isVisible=true}
 entries[#entries+1]={nodeID=id,selectionEntryID=1000+id,ranksPurchased=1}
end
nodes[1].posY=nil -- native fallback keeps missing position at zero
local expected={};for id,n in pairs(nodes)do expected[#expected+1]={id=id,y=n.posY or 0}end
table.sort(expected,function(a,b)return a.y<b.y or a.y==b.y and a.id<b.id end)
local reads=0
function InCombatLockdown()return false end
Enum={TraitNodeType={Selection=2,SubTreeSelection=3}}
C_ClassTalents={GetTraitTreeForSpec=function()return 658 end}
C_Traits={
 ResetTree=function()for _,n in pairs(nodes)do n.ranksPurchased=0 end;return true end,
 GetNodeInfo=function(_,id)
  reads=reads+1;local out={};for k,v in pairs(nodes[id])do out[k]=v end;return out
 end,
 CanPurchaseRank=function(_,id)return nodes[id].ranksPurchased<1 end,
 PurchaseRank=function(_,id)nodes[id].ranksPurchased=nodes[id].ranksPurchased+1;purchases[#purchases+1]=id;return true end,
}
assert(loadfile('addon/LycheeTalent/Talents.lua'))('LycheeTalent',A)
-- Semantic terminal condition, independent of sort/metadata implementation.
A.Talents.Matches=function()
 for id,n in pairs(nodes)do if n.ranksPurchased~=1 then return false end end;return true
end
assert(A.Talents:StageEntries(1,entries))
assert(#purchases==80)
for i,id in ipairs(purchases)do assert(id==expected[i].id,'native position and ID tie-break order changed')end
assert(reads<=80*3,'StageEntries repeatedly allocates native node metadata in its sort comparator: '..reads)
print('PASS stage order: stable native positions, ID ties/missing position, live purchased ranks; nodeReads='..reads)
