local _,A=...
local I={}
A.Icons=I

local Spell=IconDataProviderIconType.Spell
local Item=IconDataProviderIconType.Item
local prefix=[[INTERFACE\ICONS\]]
local question=[[INTERFACE\ICONS\INV_MISC_QUESTIONMARK]]
local P={}

function I:Create()
    local extraMap={}
    IconDataProviderMixin:FillOutExtraIconsMapWithSpells(extraMap)
    IconDataProviderMixin:FillOutExtraIconsMapWithTalents(extraMap)
    local icons={[Spell]={},[Item]={}}
    GetLooseMacroIcons(icons[Spell])
    GetLooseMacroItemIcons(icons[Item])
    GetMacroIcons(icons[Spell])
    GetMacroItemIcons(icons[Item])
    return setmetatable({icons=icons,extraIcons=GetKeysArray(extraMap),requestedIconTypes=IconDataProvider_GetAllIconTypes()},
        {__index=P})
end

function P:SetIconTypes(iconTypes)
    self.requestedIconTypes=iconTypes or IconDataProvider_GetAllIconTypes()
end

function P:GetNumIcons()
    local n=1
    if tContains(self.requestedIconTypes,Spell) then n=n+#self.extraIcons end
    for _,iconType in pairs(self.requestedIconTypes) do n=n+#self.icons[iconType] end
    return n
end

function P:GetIconByIndex(index)
    if index==1 then return question end
    index=index-1
    if tContains(self.requestedIconTypes,Spell) then
        if index<=#self.extraIcons then return self.extraIcons[index] end
        index=index-#self.extraIcons
    end
    for _,iconType in pairs(self.requestedIconTypes) do
        local list=self.icons[iconType]
        if index<=#list then
            local texture=list[index]
            return tonumber(texture) or prefix..texture
        end
        index=index-#list
    end
end

function P:Release()
    self.icons=nil
    self.extraIcons=nil
    self.requestedIconTypes=nil
end
