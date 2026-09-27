-- Actual shipped data, isolated Lua 5.1 heap; not a game-native memory counter.
local class=arg[1]or'MAGE'
collectgarbage('collect');local before=collectgarbage('count')
local started=os.clock()
assert(loadfile('addon/LycheeTalent_Data_'..class..'/Data.lua'))()
local loadMS=(os.clock()-started)*1000
collectgarbage('collect');local retained=collectgarbage('count')-before
local pack=assert(LycheeTalentData[class]);local builds=pack.builds;local count,packedBytes,versions=0,0,{}
for _,b in ipairs(builds)do
    count=count+1
    assert(type(b.nodes)=='string','published nodes must be packed')
    if not versions[b.version]then packedBytes=packedBytes+#b.nodes end
    versions[b.version]=true
end
local variants=0;for _ in pairs(versions)do variants=variants+1 end
print(string.format('DATA %s builds=%d variants=%d packedBytes=%d retainedKiB=%.1f loadMS=%.2f',class,count,variants,packedBytes,retained,loadMS))
if arg[2]then assert(retained<=tonumber(arg[2]),'retained data exceeds regression budget')end
