-- Temporary bounded tracing for the reported allocation spike during a real
-- talent switch. No native APIs, macro contents or saved layouts are wrapped.
local _,A=...
local P={revision="20261031-switch-allocation",limit=32}
A.Audit=P
LycheeTalentAudit=P
local targets={
    Talents={"Code","Validate","Entries","ReadEntries","Matches","StageEntries","Export"},
    Apply={"Start","Advance","OnEvent","StageWorking","MatchesWorking","CompleteWorking","Finish","CurrentBuildID","InvalidateCurrent"},
    ActionBars={"CapturePhysical","Capture","Get","SaveLayout","RestorePhysical","Restore","ObserveSlots","ObserveMacros","ResumeSpec"},
    Macros={"Scan","Sync","Current","Pack","Physical","Refresh"},
    UI={"Refresh","Toggle","UpdateHeroControls","ShowReminder"},
    TalentEx={"Inspect"},
}
local function pack(...)return {n=select("#",...),...} end
function P:Stop()
    self.enabled=false
    if self.timer then self.timer:Cancel();self.timer=nil end
    for _,binding in ipairs(self.bindings or {})do
        if binding.object[binding.key]==binding.wrapper then binding.object[binding.key]=binding.original end
    end
    self.bindings=nil
    if self.started then self.stopped=GetTime() end
end
function P:Start(seconds)
    self:Stop()
    self.started=GetTime();self.stopped=nil;self.records={};self.events={};self.largest={};self.stack={};self.bindings={}
    self.enabled=true
    for name,methods in pairs(targets)do
        local object=A[name]
        if object then
            for _,key in ipairs(methods)do
                local original=object[key]
                if type(original)=="function" then
                    local label=name.."."..key
                    local function wrapper(owner,...)
                        if not P.enabled or #P.stack>=16 then return original(owner,...) end
                        if label=="Apply.InvalidateCurrent" then
                            local event=(...)
                            if type(event)=="string" and #event<=80 then P.events[event]=(P.events[event] or 0)+1 end
                        end
                        local span={ms=debugprofilestop(),heap=collectgarbage("count"),childMS=0,childHeap=0,
                            stage=A.Apply and A.Apply.op and A.Apply.op.stage or "none"}
                        P.stack[#P.stack+1]=span
                        local result=pack(pcall(original,owner,...))
                        local delta=collectgarbage("count")-span.heap
                        local elapsed=debugprofilestop()-span.ms
                        P.stack[#P.stack]=nil
                        local parent=P.stack[#P.stack]
                        if parent then parent.childMS=parent.childMS+elapsed;parent.childHeap=parent.childHeap+delta end
                        local record=P.records[label]
                        if not record then record={calls=0,ms=0,heapDeltaKiB=0,exclusiveMS=0,exclusiveHeapDeltaKiB=0,
                            maxMS=0,maxHeapDeltaKiB=0,gcDrops=0,errors=0};P.records[label]=record end
                        record.calls=record.calls+1;record.ms=record.ms+elapsed;record.heapDeltaKiB=record.heapDeltaKiB+delta
                        record.exclusiveMS=record.exclusiveMS+elapsed-span.childMS
                        record.exclusiveHeapDeltaKiB=record.exclusiveHeapDeltaKiB+delta-span.childHeap
                        record.maxMS=math.max(record.maxMS,elapsed);record.maxHeapDeltaKiB=math.max(record.maxHeapDeltaKiB,delta)
                        if delta<0 then record.gcDrops=record.gcDrops+1 end
                        if not result[1] then record.errors=record.errors+1 end
                        if delta>256 or elapsed>10 then
                            P.largest[#P.largest+1]={label=label,stage=span.stage,ms=elapsed,heapDeltaKiB=delta}
                            table.sort(P.largest,function(a,b)return a.heapDeltaKiB>b.heapDeltaKiB end)
                            if #P.largest>P.limit then P.largest[#P.largest]=nil end
                        end
                        if not result[1] then error(result[2],0) end
                        return unpack(result,2,result.n)
                    end
                    object[key]=wrapper
                    self.bindings[#self.bindings+1]={object=object,key=key,original=original,wrapper=wrapper}
                end
            end
        end
    end
    self.timer=C_Timer.NewTimer(math.min(120,math.max(1,seconds or 120)),function()P:Stop()end)
end
function P:Snapshot()
    local records={}
    for label,record in pairs(self.records or {})do
        local copy={};for key,value in pairs(record)do copy[key]=value end;records[label]=copy
    end
    local largest={}
    for _,row in ipairs(self.largest or {})do
        local copy={};for key,value in pairs(row)do copy[key]=value end;largest[#largest+1]=copy
    end
    local events={};for key,value in pairs(self.events or {})do events[key]=value end
    return {revision=self.revision,enabled=self.enabled==true,started=self.started,stopped=self.stopped,
        scope="actual-addon-calls-natural-gc-inclusive-and-nested-exclusive-deltas",records=records,events=events,largest=largest}
end
