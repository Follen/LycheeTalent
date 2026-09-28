-- Feed the full pinned Blizzard IconDataProvider.lua source on stdin.
-- Compare the addon adapter with the real mixin under deterministic game API stubs.
local source=io.read("*a"):gsub("^\239\187\191","")
assert(source:find("IconDataProviderMixin:Release",1,true),"provider source required on stdin")

local gcCalls,refreshes,itemRefreshes=0,0,0
local env=setmetatable({
    EnumUtil={MakeEnum=function()return {Spell=1,Item=2}end},
    GetValuesArray=function(t)return {t.Spell,t.Item}end,
    GetKeysArray=function(t)
        local keys={};for key in pairs(t)do keys[#keys+1]=key end
        table.sort(keys);return keys
    end,
    GetLooseMacroIcons=function(out)refreshes=refreshes+1;out[1]="111";out[2]="SPELL_PATH" end,
    GetLooseMacroItemIcons=function(out)itemRefreshes=itemRefreshes+1;out[1]="222" end,
    GetMacroIcons=function(out)out[3]="333" end,
    GetMacroItemIcons=function(out)out[2]="ITEM_PATH" end,
    collectgarbage=function()gcCalls=gcCalls+1 end,
    tContains=function(t,value)
        for _,candidate in ipairs(t)do if candidate==value then return true end end
        return false
    end,
},{__index=_G})
local nativeChunk=assert(loadstring(source,"@pinned/IconDataProvider.lua"))
setfenv(nativeChunk,env);nativeChunk()
function env.IconDataProviderMixin:FillOutExtraIconsMapWithSpells(map)map[9001]=true end
function env.IconDataProviderMixin:FillOutExtraIconsMapWithTalents(map)map[9002]=true end

local A={}
local adapterChunk=assert(loadfile("addon/LycheeTalent/Icons.lua"))
setfenv(adapterChunk,env);adapterChunk("LycheeTalent",A)
local native=setmetatable({},{__index=env.IconDataProviderMixin})
native:Init(env.IconDataProviderExtraType.Spellbook)
local adapter=A.Icons:Create()
assert(refreshes==1 and itemRefreshes==1,"opening common icons must not enumerate either full catalog")
assert(adapter:GetNumIcons()==3,"common includes question mark and current character icons")
local spell,item=env.IconDataProviderIconType.Spell,env.IconDataProviderIconType.Item
local function compare(filter)
    native:SetIconTypes(filter)
    adapter:SetIconTypes(filter)
    local count=native:GetNumIcons()
    assert(adapter:GetNumIcons()==count,"count differs")
    for index=1,count+1 do
        assert(adapter:GetIconByIndex(index)==native:GetIconByIndex(index),
            "icon differs at index "..index)
    end
    return count
end
assert(compare({spell})==6,"spell count includes two extras")
assert(refreshes==2 and itemRefreshes==1,"spell tab loads only the spell catalog")
assert(compare({item})==3,"item count excludes spell extras")
adapter:SetIconTypes(nil)
assert(adapter:GetNumIcons()==3,"nil filter restores common icons")
assert(refreshes==2 and itemRefreshes==2,"each category is built once")

native:Release()
assert(gcCalls==1,"native final release invokes global GC")
adapter:Release();adapter:Release()
assert(not adapter.icons and not adapter.extraIcons and not adapter.requestedIconTypes,
    "adapter release drops catalog references")
assert(gcCalls==1,"adapter release must not invoke global GC")

env.IconDataProviderMixin.Init=function()error("adapter called native Init")end
env.IconDataProviderMixin.Release=function()error("adapter called native Release")end
for i=1,100 do
    local provider=A.Icons:Create()
    provider:SetIconTypes({item})
    assert(provider:GetNumIcons()==3 and provider:GetIconByIndex(3)==[[INTERFACE\ICONS\ITEM_PATH]])
    provider:Release()
    assert(provider.icons==nil and gcCalls==1)
end
assert(refreshes==2 and itemRefreshes==2,"100 reopen cycles reuse catalogs")
local selected=A.Icons:Create("hero-atlas")
assert(selected:GetNumIcons()==4 and selected:GetIconByIndex(2)=="hero-atlas","selected icon is available in common")
selected:Release()
selected=A.Icons:Create(9001)
assert(selected:GetNumIcons()==3,"selected spell is not duplicated")
selected:Release()
env.IconDataProviderMixin.FillOutExtraIconsMapWithSpells=function(_,map)map[9003]=true end
local fresh=A.Icons:Create()
assert(fresh:GetIconByIndex(3)==9003,"common icons refresh after character changes")
fresh:Release()
print("PASS icon adapter: lazy categories, pinned-source parity, 100 reopens reuse cache, current icon, refreshed spells, zero adapter GC")
