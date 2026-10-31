local name, A = ...
A.name = name
function A:GetSpec()
    local index=C_SpecializationInfo.GetSpecialization()
    if type(index)~="number" or index<=0 or index%1~=0 then return nil end
    local spec,name,description,icon,role,primaryStat,pointsSpent,background,previewPointsSpent,isUnlocked=C_SpecializationInfo.GetSpecializationInfo(index)
    if type(spec)=="number" and spec>0 and spec%1==0 then
        return spec,name,description,icon,role,primaryStat,pointsSpent,background,previewPointsSpent,isUnlocked
    end
end
function A:Message(key)
    -- Actionable failures stay beside the controls while the panel is open.
    if key=="APPLYING" or key=="APPLY_SUCCESS" or key=="BARS_PENDING" then return end
    if self.UI and self.UI.ShowError and self.UI:ShowError(key) then self.UI:Refresh();return end
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
