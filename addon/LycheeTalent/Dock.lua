local _,A=...
local D={}
A.Dock=D

function D:WatchTalentEx()
    local frame=TalentLoadoutExMainFrame
    if not frame or self.talentEx==frame then return end
    self.talentEx=frame
    local function reposition()
        if A.UI.frame and A.UI.frame:IsShown() then A.UI:Scale() end
    end
    frame:HookScript("OnShow",reposition)
    frame:HookScript("OnHide",reposition)
    frame:HookScript("OnSizeChanged",reposition)
end
function D:Anchor()
    self:WatchTalentEx()
    if self.talentEx and self.talentEx:IsShown() then return self.talentEx end
    return PlayerSpellsFrame
end

function D:Show()
    self:WatchTalentEx()
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
    self.events:SetScript("OnEvent",function(_,event,addon)
        if event=="ADDON_LOADED" and (addon=="TalentLoadoutsEx" or addon=="Blizzard_PlayerSpells") and not D.anchorTimer then
            -- Discover after other addons finish handling this same load event.
            D.anchorTimer=C_Timer.NewTimer(0,function()
                D.anchorTimer=nil;D:WatchTalentEx()
                if A.UI.frame and A.UI.frame:IsShown() then A.UI:Scale() end
            end)
        end
        if D:Attach() then
            D.events:UnregisterEvent("PLAYER_REGEN_ENABLED")
            if event=="PLAYER_REGEN_ENABLED" then D:Show() end
        end
    end)
    if self:Attach() then self.events:UnregisterEvent("PLAYER_REGEN_ENABLED") end
end
