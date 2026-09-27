local _,A=...
local D={}
A.Dock=D

function D:Show()
    if not self.host or not self.host:IsShown() or self.collapsed then return end
    if PlayerSpellsFrame:IsInspecting() then return end
    if not A.UI.frame then
        if InCombatLockdown() then self.events:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
        A.UI:Create()
    end
    local f=A.UI.frame
    if f:IsShown() and not A.UI.closing then return end
    A.UI.closing=false
    f:Show()
    A.Motion:Presence(f,true)
end

function D:Attach()
    if self.host then return true end
    local native=PlayerSpellsFrame
    if not native or not native.TalentsFrame or InCombatLockdown() then return false end
    self.host=native.TalentsFrame
    self.host:HookScript("OnShow",function() D.collapsed=false; D:Show() end)
    self.host:HookScript("OnHide",function()
        D.collapsed=false
        if A.UI.frame then A.UI.frame:Hide() end
    end)
    native:HookScript("OnHide",function()
        D.collapsed=false
        if A.UI.frame then A.UI.frame:Hide() end
    end)
    native:HookScript("OnSizeChanged",function() if A.UI.frame and A.UI.frame:IsShown() then A.UI:Scale(); A.UI:Refresh() end end)
    self:Show()
    return true
end

function D:Init()
    if self.events then return end
    self.events=CreateFrame("Frame")
    self.events:RegisterEvent("ADDON_LOADED")
    self.events:RegisterEvent("PLAYER_REGEN_ENABLED")
    self.events:SetScript("OnEvent",function(_,event)
        if D:Attach() then
            D.events:UnregisterEvent("ADDON_LOADED")
            D.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
            if event=="PLAYER_REGEN_ENABLED" then D:Show() end
        end
    end)
    if self:Attach() then self.events:UnregisterAllEvents() end
end
