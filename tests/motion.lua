-- Active transitions must restore anchors and never invoke a superseded navigation.
local function frame()
 local f={shown=true,alpha=1,anchor={"TOPLEFT",false,"TOPLEFT",15,-100},scripts={}}
 function f:GetPoint()return unpack(self.anchor)end
 function f:ClearAllPoints()end
 function f:SetPoint(...)self.anchor={...}end
 function f:SetAlpha(a)self.alpha=a end
 function f:SetSize(w,h)self.width=w;self.height=h end
 function f:IsShown()return self.shown end
 function f:Show()self.shown=true end
 function f:Hide()self.shown=false end
 function f:SetScript(k,v)self.scripts[k]=v end
 return f
end
CreateFrame=frame
local combat=false
InCombatLockdown=function()return combat end
local A={Store={db={}}}
assert(loadfile('addon/LycheeTalent/Motion.lua'))('LycheeTalent',A)
local M=A.Motion
local first,second=frame(),frame()
local oldDone,newDone=0,0
M:Slide(first,1,true,function()oldDone=oldDone+1 end)
M.driver.scripts.OnUpdate(nil,.04)
assert(first.alpha<1 and first.anchor[4]~=15)
M:Slide(second,-1,false,function()newDone=newDone+1 end)
assert(first.alpha==1 and first.anchor[4]==15 and oldDone==0,'interrupt restores old surface and cancels callback')
M.driver.scripts.OnUpdate(nil,.2)
assert(newDone==1 and second.alpha==1 and second.anchor[4]==15,'arrival settles exactly once')
assert(not M.driver.shown and not M.driver.scripts.OnUpdate,'idle has no animation driver')
M:Slide(first,1)
first:Hide();M.driver.scripts.OnUpdate(nil,.01)
assert(not M.frame and first.alpha==1,'hidden page stops and resets')
first:Show();M:Slide(first,1,true,function()oldDone=oldDone+1 end)
M:Finish(second)
assert(first.alpha==1 and first.anchor[4]==15 and oldDone==0,'parent cancellation restores active child')
M:Slide(first,1);combat=true;M.driver.scripts.OnUpdate(nil,.01)
assert(not M.frame and not M.driver.scripts.OnUpdate,'combat stops active transition')
combat=false;A.Store.db.reducedMotion=true
M:Slide(first,1,true,function()oldDone=oldDone+1 end)
assert(oldDone==1 and not M.frame,'reduced motion applies navigation immediately')
A.Store.db.reducedMotion=false
M:Presence(first,true);M.driver.scripts.OnUpdate(nil,.1)
M:Slide(second,1)
assert(first.alpha==1 and first.anchor[4]==15,'navigation interrupts root presence cleanly')
M:Finish(second)
M:Brand(first,54);M.brandDriver.scripts.OnUpdate(nil,.16)
assert(first.width>54 and first.height<54,'Lychee logo starts with squash')
local running=M.brand;M:Brand(first,54);assert(M.brand==running,'hover does not restart an active bounce')
M.brandDriver.scripts.OnUpdate(nil,1.3)
assert(not M.brand and first.width==54 and first.height==54 and first.anchor[4]==15,'bounce settles to original geometry')
assert(not M.brandDriver.shown and not M.brandDriver.scripts.OnUpdate,'bounce leaves no idle driver')
M:Brand(first,54);first:Hide();M.brandDriver.scripts.OnUpdate(nil,.1)
assert(not M.brand,'hidden logo cancels bounce')
first:Show();A.Store.db.reducedMotion=true;M:Brand(first,54);assert(not M.brand,'reduced motion skips bounce')
print('PASS motion: cancellation, callback ownership, hidden/combat cleanup, reduced motion, shared driver')
