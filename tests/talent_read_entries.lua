-- Differential oracle: pinned Blizzard export/import, not a reimplemented
-- rank allocator. The native Import.lua hash matches wow-ui-source 15881d5.
bit=require("bit");getn=table.getn
function tInvert(t)local r={};for k,v in pairs(t)do r[v]=k end;return r end
function CreateFromMixins(...)local out={};for i=1,select('#',...)do for k,v in pairs(select(i,...))do out[k]=v end end;return out end
function CreateAndInitFromMixin(m,...)local r=CreateFromMixins(m);r:Init(...);return r end
function Mixin(t,...)for i=1,select('#',...)do for k,v in pairs(select(i,...))do t[k]=v end end;return t end
StaticPopupDialogs={};ERROR_COLOR={WrapTextInColorCode=function(_,s)return s end}
dofile('analyze/Blizzard/ExportUtil.lua');dofile('analyze/Blizzard/Import.lua')
Enum={TraitNodeType={Single=0,Tiered=1,Selection=2,SubTreeSelection=3}}
local A={GetSpec=function()return 62 end}
InCombatLockdown=function()return false end
local function copy(t)local out={};for k,v in pairs(t)do out[k]=type(v)=='table' and copy(v)or v end;return out end
local nodes,order,entryInfo={},{},{}
local function add(id,kind,max,ranks,active,entries,selection,subtree)
 order[#order+1]=id;local ids={}
 for _,e in ipairs(entries)do ids[#ids+1]=e[1];entryInfo[e[1]]={maxRanks=e[2],subTreeID=e[3]}end
 nodes[id]={ID=id,type=kind,maxRanks=max,ranksPurchased=ranks,activeRank=active,entryIDs=ids,
  activeEntry=selection and {entryID=selection}or nil,subTreeID=subtree}
end
add(101,0,3,2,2,{{1001,3}},1001)
add(102,0,1,0,1,{{1002,1}},1002)
add(103,3,1,1,1,{{1003,1,51},{1004,1,53}},1004)
add(104,0,1,0,1,{{1005,1}},1005,51)
add(105,0,1,0,1,{{1006,1}},nil,53)
-- The reported Tiered failure shape is one node split into 1/2/1 entries.
add(110417,1,4,4,4,{{2001,1},{2002,2},{2003,1}},2003)
add(107,1,4,2,2,{{2011,1},{2012,2},{2013,1}},2012)
add(108,1,4,0,1,{{2021,1},{2022,2},{2023,1}},2021)
add(109,0,1,0,0,{{1009,1}},nil)
add(110,2,1,0,1,{{1010,1},{1011,1}},1011)
add(111,2,1,0,1,{{3001,1},{3002,1},{3003,1},{3004,1},{3005,1}},3005)
add(112,2,1,1,1,{{3011,1},{3012,1},{3013,1},{3014,1}},3014)
add(113,0,3,2,3,{{1013,3}},1013)
local snapshots={[1]=copy(nodes),[2]=copy(nodes)}
snapshots[2][101].ranksPurchased=1;snapshots[2][101].activeRank=1
snapshots[2][103].activeEntry.entryID=1003
snapshots[2][110417].ranksPurchased=3;snapshots[2][110417].activeRank=3
local nodeReads,treeReads,exports,imports=0,0,0,0
local hash={};for i=1,16 do hash[i]=i end
C_ClassTalents={GetActiveConfigID=function()return 1 end,GetTraitTreeForSpec=function()return 658 end}
C_Traits={GetTreeHash=function()return copy(hash)end,GetLoadoutSerializationVersion=function()return 2 end,
 GetTreeNodes=function()treeReads=treeReads+1;return copy(order)end,
 GetNodeInfo=function(config,id)nodeReads=nodeReads+1;return snapshots[config][id] and copy(snapshots[config][id])end,
 GetEntryInfo=function(_,id)return entryInfo[id] and copy(entryInfo[id])end}
local frame=CreateFromMixins(ClassTalentImportExportMixin);PlayerSpellsFrame={TalentsFrame=frame}
assert(loadfile('addon/LycheeTalent/Talents.lua'))('LycheeTalent',A)
local makeExport,makeImport=ExportUtil.MakeExportDataStream,ExportUtil.MakeImportDataStream
ExportUtil.MakeExportDataStream=function(...)exports=exports+1;return makeExport(...)end
ExportUtil.MakeImportDataStream=function(...)imports=imports+1;return makeImport(...)end
local function oracle(config)
 local stream=ExportUtil.MakeExportDataStream()
 frame:WriteLoadoutHeader(stream,2,62,C_Traits.GetTreeHash(658));frame:WriteLoadoutContent(stream,config,658)
 local input=ExportUtil.MakeImportDataStream(stream:GetExportString())
 assert(frame:ReadLoadoutHeader(input))
 return frame:ConvertToImportLoadoutEntryInfo(config,658,frame:ReadLoadoutContent(input,658))
end
local function same(a,b)
 assert(#a==#b,'entry count differs')
 for i,e in ipairs(a)do for _,k in ipairs({'nodeID','selectionEntryID','ranksPurchased','ranksGranted'})do
  assert(e[k]==b[i][k],string.format('entry %d %s differs: %s / %s',i,k,tostring(e[k]),tostring(b[i][k])))
 end end
end
local function differential(config,label)
 local expected=oracle(config)
 nodeReads,treeReads,exports,imports=0,0,0,0
 local actual=A.Talents:ReadEntries(config);same(expected,actual)
 print(string.format('READ_ENTRIES %s nodes=%d trees=%d exportStreams=%d importStreams=%d entries=%d',label,nodeReads,treeReads,exports,imports,#actual))
 assert(exports==0 and imports==0,'ReadEntries still serializes/export-imports native tree')
 assert(treeReads==1 and nodeReads==#order,'ReadEntries must read each native node exactly once')
 return actual
end
local actual=differential(1,'active')
differential(2,'saved')
local tiered={};for _,e in ipairs(actual)do if e.nodeID==110417 then tiered[#tiered+1]=e.ranksPurchased end end
assert(table.concat(tiered,',')=='1,2,1','Tiered ranks must use native per-entry allocation')
local effective={};for _,e in ipairs(actual)do if e.nodeID~=104 then effective[#effective+1]=e end end
assert(A.Talents:Matches(1,effective),'inactive hero grant normalization must remain unchanged')
local full=snapshots[1];snapshots[1]=copy(full)
for _,n in pairs(snapshots[1])do n.activeRank=0;n.ranksPurchased=0 end
assert(#differential(1,'empty-draft')==0)
snapshots[1][101].activeRank=1;snapshots[1][101].ranksPurchased=1
differential(1,'partial-draft');snapshots[1]=full
-- Purchased choices retain the native 1..4 export validation. Granted-only
-- choices above deliberately use entry 5 and must not take that export branch.
local original=snapshots[1][112].activeEntry
for _,invalid in ipairs({9999,3015})do
 snapshots[1][112].entryIDs[5]=3015;snapshots[1][112].activeEntry={entryID=invalid}
 assert(not pcall(oracle,1),'oracle should reject invalid purchased choice')
 assert(not pcall(A.Talents.ReadEntries,A.Talents,1),'direct reader must reject invalid purchased choice')
end
snapshots[1][112].entryIDs[5]=nil;snapshots[1][112].activeEntry=original
-- A later/legacy frame can implement its converter without these helpers.
-- Its unchanged native roundtrip is still a supported fallback.
local nativeConvert=frame.ConvertToImportLoadoutEntryInfo
local fallback=CreateFromMixins(frame)
fallback.CreateImportLoadoutEntryInfoFromSingleNode=false;fallback.CreateImportLoadoutEntryInfoFromTieredNode=false
fallback.ConvertToImportLoadoutEntryInfo=function(_,...)return nativeConvert(ClassTalentImportExportMixin,...)end
PlayerSpellsFrame.TalentsFrame=fallback
local expected=oracle(1);exports,imports=0,0
same(expected,A.Talents:ReadEntries(1));assert(exports==1 and imports==1,'missing helpers must retain native roundtrip')
PlayerSpellsFrame.TalentsFrame=frame
-- A protocol version change opts out of the known v2 flags and follows native.
local version=C_Traits.GetLoadoutSerializationVersion
C_Traits.GetLoadoutSerializationVersion=function()return 3 end
exports,imports=0,0;same(expected,A.Talents:ReadEntries(1));assert(exports==1 and imports==1)
C_Traits.GetLoadoutSerializationVersion=version
local nodeInfo=C_Traits.GetNodeInfo
C_Traits.GetNodeInfo=function(config,id)if id==order[3] then return nil end;return nodeInfo(config,id)end
assert(A.Talents:ReadEntries(1)==nil,'an unavailable node must not produce a partial success')
C_Traits.GetNodeInfo=nodeInfo
-- Real same-build Mage node/entry definitions and captured rank snapshots.
local data=dofile('tests/fixtures/mage-tree-69933.lua')
local replay=dofile('tests/fixtures/mage-staging-69933.lua')
order=copy(data.order);entryInfo={}
for id,e in pairs(data.entries)do entryInfo[tonumber(id)]={maxRanks=e.MaxRanks,subTreeID=e.TraitSubTreeID~=0 and e.TraitSubTreeID or nil}end
local function mage(entries)
 local out={}
 for id,n in pairs(data.nodes)do
  local node=copy(n);node.ranksPurchased=0;node.activeRank=0;node.activeEntry={entryID=node.entryIDs[1]};out[tonumber(id)]=node
 end
 for _,e in ipairs(entries)do
  local n=out[e.nodeID];n.ranksPurchased=n.ranksPurchased+(e.ranksPurchased or 0)
  n.activeRank=n.activeRank+(e.ranksPurchased or 0)+(e.ranksGranted or 0);n.activeEntry={entryID=e.selectionEntryID}
 end
 return out
end
snapshots[1]=mage(replay.entries);snapshots[2]=mage({})
snapshots[2]=mage(A.Talents:Entries(replay.original,2))
differential(1,'real-mage-active');differential(2,'real-mage-saved')
print('PASS native-helper entries: active/saved, free/inactive grants, Tiered 1/2/1 and partial/granted ranks, choice bounds, empty/partial drafts, fallback')
