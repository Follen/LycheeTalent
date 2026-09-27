-- Compare a generated class shard to the complete public SQLite payload rendered
-- as Lua by test_data_publication.py. This runs in a fresh Lua 5.1 process.
local class,expectedPath=arg[1],arg[2]
local expected=assert(loadfile(expectedPath))()
assert(loadfile('addon/LycheeTalent_Data_'..class..'/Data.lua'))()
local actual=assert(LycheeTalentData[class])

local function unpackNodes(packed)
    assert(packed:gsub('%d+:%d+;','')=='','malformed packed nodes')
    local result={}
    for entry,rank in packed:gmatch('(%d+):(%d+);') do
        result[#result+1]={tonumber(entry),tonumber(rank)}
    end
    return result
end

local function equal(want,got,path)
    if path:match('%.nodes$') and type(got)=='string' then got=unpackNodes(got) end
    assert(type(want)==type(got),path..': type mismatch')
    if type(want)~='table' then assert(want==got,path..': value mismatch');return end
    for key,value in pairs(want) do
        assert(got[key]~=nil,path..': missing '..tostring(key))
        equal(value,got[key],path..'.'..tostring(key))
    end
    for key in pairs(got) do assert(want[key]~=nil,path..': extra '..tostring(key)) end
end

equal(expected,actual,class)
local total=0
for _,build in ipairs(actual.builds) do
    assert(type(build.nodes)=='string','unpacked nodes in '..build.id)
    total=total+1
end
print('PASS '..class..' builds='..total)
