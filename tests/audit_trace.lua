local timers={}
C_Timer={NewTimer=function(_,fn)local timer={fn=fn,Cancel=function(self)self.cancelled=true end};timers[#timers+1]=timer;return timer end}
local clock=0
GetTime=function()return clock end
debugprofilestop=function()clock=clock+.01;return clock end
local A={Talents={},Apply={}}
local inner=function(self,a)return nil,a,"tail" end
A.Talents.ReadEntries=inner
A.Talents.Matches=function(self,value)
    local a,b,c=self:ReadEntries(value)
    assert(a==nil and b==value and c=="tail")
    return "matched",nil,value
end
A.Apply.Start=function()error("expected-original-error")end
A.Apply.InvalidateCurrent=function()end
assert(loadfile("addon/LycheeTalent/Audit.lua"))("LycheeTalent",A)
local originalMatches=A.Talents.Matches
A.Audit:Start(2)
assert(A.Talents.ReadEntries~=inner)
local result={n=0}
local function preserve(...)result.n=select("#",...);result.values={...}end
preserve(A.Talents:Matches(42))
assert(result.n==3 and result.values[1]=="matched" and result.values[2]==nil and result.values[3]==42,"nil positions and return count survive tracing")
assert(#A.Audit.stack==0 and A.Audit.records["Talents.Matches"].calls==1 and A.Audit.records["Talents.ReadEntries"].calls==1)
A.Apply:InvalidateCurrent("TRAIT_CONFIG_UPDATED")
local ok,why=pcall(A.Apply.Start,A.Apply)
assert(not ok and why:find("expected%-original%-error") and #A.Audit.stack==0,"errors still propagate and tracing unwinds")
assert(A.Audit.records["Apply.Start"].errors==1)
local snapshot=A.Audit:Snapshot()
assert(snapshot.events.TRAIT_CONFIG_UPDATED==1 and snapshot.records["Talents.Matches"].exclusiveMS>0)
snapshot.records["Talents.Matches"].calls=999
assert(A.Audit.records["Talents.Matches"].calls==1,"snapshot cannot mutate counters")
timers[#timers].fn()
assert(not A.Audit.enabled and not A.Audit.bindings and A.Talents.ReadEntries==inner and A.Talents.Matches==originalMatches,"deadline restores every original method")
A.Audit:Start(1)
local replacement=function()return "new-owner"end
A.Talents.ReadEntries=replacement
A.Audit:Stop()
assert(A.Talents.ReadEntries==replacement,"stop cannot replace a later owner")
assert(A.Talents:ReadEntries()=="new-owner")
-- The real TOC/Core path starts the bounded session after normal initialization.
local initialized=0
A.Store={Init=function()initialized=initialized+1 end}
A.ActionBars={Init=function()initialized=initialized+1 end}
A.Reminders={RefreshSettings=function()initialized=initialized+1 end}
A.Dock={Init=function()initialized=initialized+1 end}
SlashCmdList={}
local bootFrame
CreateFrame=function()
    bootFrame={events={}}
    function bootFrame:RegisterEvent(event)self.events[event]=true end
    function bootFrame:UnregisterEvent(event)self.events[event]=nil end
    function bootFrame:SetScript(_,handler)self.handler=handler end
    return bootFrame
end
assert(loadfile("addon/LycheeTalent/Core.lua"))("LycheeTalent",A)
bootFrame.handler(bootFrame,"ADDON_LOADED","AnotherAddon")
assert(initialized==0 and not A.Audit.enabled)
bootFrame.handler(bootFrame,"ADDON_LOADED","LycheeTalent")
assert(initialized==4 and A.Audit.enabled and not bootFrame.events.ADDON_LOADED)
timers[#timers].fn()
assert(not A.Audit.enabled and A.Talents.ReadEntries==replacement)
print("PASS bounded audit: original arguments/returns/errors, nested deltas, immutable snapshots, timed restoration and later-owner protection")
