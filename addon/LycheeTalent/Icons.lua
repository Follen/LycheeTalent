local _,A=...
local I={}
A.Icons=I

local Spell=IconDataProviderIconType.Spell
local Item=IconDataProviderIconType.Item
local prefix=[[INTERFACE\ICONS\]]
local question=[[INTERFACE\ICONS\INV_MISC_QUESTIONMARK]]
local P={}
-- At most two static catalogs, populated only when their tab is selected.
-- Rebuilding these on every open creates large amounts of short-lived garbage.
local catalogs={}
local function catalog(iconType)
    if catalogs[iconType] then return catalogs[iconType] end
    local icons={}
    if iconType==Spell then GetLooseMacroIcons(icons);GetMacroIcons(icons)
    elseif iconType==Item then GetLooseMacroItemIcons(icons);GetMacroItemIcons(icons) end
    for i,value in ipairs(icons) do icons[i]=tonumber(value) or value end
    catalogs[iconType]=icons
    return icons
end

function I:Create(selectedIcon)
    local extraMap={}
    IconDataProviderMixin:FillOutExtraIconsMapWithSpells(extraMap)
    IconDataProviderMixin:FillOutExtraIconsMapWithTalents(extraMap)
    selectedIcon=tonumber(selectedIcon) or selectedIcon
    if selectedIcon==question or selectedIcon==134400 or extraMap[selectedIcon] then selectedIcon=nil end
    return setmetatable({icons={},extraIcons=GetKeysArray(extraMap),selectedIcon=selectedIcon},
        {__index=P})
end

function P:SetIconTypes(iconTypes)
    self.requestedIconTypes=iconTypes
    for _,iconType in ipairs(iconTypes or {}) do self.icons[iconType]=catalog(iconType) end
end

function P:GetNumIcons()
    local n=1
    if not self.requestedIconTypes then return n+#self.extraIcons+(self.selectedIcon and 1 or 0) end
    if tContains(self.requestedIconTypes,Spell) then n=n+#self.extraIcons end
    for _,iconType in pairs(self.requestedIconTypes) do n=n+#self.icons[iconType] end
    return n
end

function P:GetIconByIndex(index)
    if index==1 then return question end
    index=index-1
    if not self.requestedIconTypes then
        if self.selectedIcon then
            if index==1 then return self.selectedIcon end
            index=index-1
        end
        return self.extraIcons[index]
    end
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
    self.selectedIcon=nil
end
