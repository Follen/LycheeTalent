local name, A = ...
A.name = name
function A:GetSpec()
    local index=C_SpecializationInfo.GetSpecialization()
    if not index then return nil end
    return C_SpecializationInfo.GetSpecializationInfo(index)
end
function A:Message(key)
    -- Progress and success are represented by the row; errors remain available
    -- in chat without adding a persistent explanation block to the sidebar.
    if key=="APPLYING" or key=="APPLY_SUCCESS" then return end
    local text=self.L[key] or key
    print("|cffd53c49"..self.L.TITLE.."|r: "..text)
end
function A:Toggle()
    if not self.Store.db then self.Store:Init() end
    if InCombatLockdown() and not self.UI.frame then self:Message("COMBAT"); return end
    self.UI:Toggle()
end
SLASH_LYCHEETALENT1="/lt"
SLASH_LYCHEETALENT2="/lycheetalent"
SlashCmdList.LYCHEETALENT=function() A:Toggle() end
local events=CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent",function(self,event,loaded)
    if loaded~=name then return end
    A.Store:Init()
    A.ActionBars:Init()
    A.Reminders:RefreshSettings()
    A.Dock:Init()
    self:UnregisterEvent("ADDON_LOADED")
end)
