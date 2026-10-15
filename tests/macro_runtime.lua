-- Native API substitute shared by macro content and event regression tests.
return function(deferred)
    local T={spec=62,slots={},native={},frames={},timers={},copies=0,writes=0,placements=0}
    local function copy(v)local out={};for k,x in pairs(v or {})do out[k]=type(x)=='table' and copy(x)or x end;return out end
    T.copy=copy
    local A={Store={character={}},GetSpec=function()return T.spec end,Message=function(_,why)T.message=why end}
    A.Apply={CurrentBuildID=function(self)
        local state=A.ActionBars:Spec(T.spec)
        if not self.op and not T.external and state.applied then return state.applied.id end
    end}
    T.A=A
    function T.emit(event,...)
        for _,frame in ipairs(T.frames)do if frame.events[event]then frame.handler(frame,event,...)end end
    end
    function T.changed(event,...)
        local args={...}
        if deferred then T.timers[#T.timers+1]=function()T.emit(event,unpack(args))end else T.emit(event,...)end
    end
    function T.settle()
        for n=1,20 do
            if #T.timers==0 then return end
            local pending=T.timers;T.timers={};for _,fn in ipairs(pending)do fn()end
        end
        error('unbounded background work')
    end
    function InCombatLockdown()return T.combat end
    function GetCursorInfo()if T.cursor then return T.cursor.kind,T.cursor.id end end
    function ClearCursor()T.cursor=nil;T.emit('CURSOR_CHANGED')end
    function GetActionInfo(slot)
        local entry=T.slots[slot]or{}
        if entry.kind=='macro' and not entry.plain then return 'macro',999,'spell' end
        return entry.kind,entry.id,entry.sub
    end
    function GetMacroInfo(index)local macro=T.native[index];if macro then return macro.name,macro.icon,macro.body end end
    C_Macro={GetSelectedMacroIcon=function(index)local m=T.native[index];return m and m.icon end}
    Constants={MacroConsts={MAX_ACCOUNT_MACROS=120,MAX_CHARACTER_MACROS=30}}
    C_ActionBar={GetActionText=function(slot)local entry=T.slots[slot];local m=entry and T.native[entry.id];return m and m.name end}
    C_Spell={PickupSpell=function(id)T.cursor={kind='spell',id=id,sub='spell'}end}
    C_Item={PickupItem=function(id)T.cursor={kind='item',id=id}end}
    function PickupAction(slot,keep)
        if keep then T.copies=T.copies+1 end
        local old=T.slots[slot];T.cursor=old and copy(old)
        if not keep then T.slots[slot]=nil end
        T.changed('ACTIONBAR_SLOT_CHANGED',slot);T.emit('CURSOR_CHANGED')
    end
    function PickupMacro(index)if T.native[index]then T.cursor={kind='macro',id=index}end;T.emit('CURSOR_CHANGED')end
    function PlaceAction(slot)
        T.placements=T.placements+1
        if T.failPlace then T.failPlace=nil;error('injected placement failure')end
        local old=T.slots[slot];T.slots[slot]=copy(T.cursor);T.cursor=old
        T.changed('ACTIONBAR_SLOT_CHANGED',slot);T.emit('CURSOR_CHANGED')
    end
    function EditMacro(index,name,icon,body)
        if T.failEdit then T.failEdit=nil;return end
        local m=assert(T.native[index]);m.name=name or m.name;m.icon=icon or m.icon;m.body=body or m.body
        T.writes=T.writes+1;T.changed('UPDATE_MACROS');return index
    end
    function CreateMacro(name,icon,body,character)
        assert(character,'managed macros must use character slots')
        if T.failCreate then T.failCreate=nil;return end
        local index=121;while T.native[index]do index=index+1 end
        assert(index<=120+Constants.MacroConsts.MAX_CHARACTER_MACROS,'native macro capacity')
        T.native[index]={name=name,icon=icon,body=body};T.writes=T.writes+1
        T.changed('UPDATE_MACROS');return index
    end
    function DeleteMacro(index)
        local limit=index<=120 and 120 or 150
        for i=index,limit-1 do T.native[i]=T.native[i+1]end;T.native[limit]=nil
        for slot,entry in pairs(T.slots)do
            if entry.kind=='macro' then
                if entry.id==index then T.slots[slot]=nil
                elseif entry.id>index and entry.id<=limit then entry.id=entry.id-1 end
            end
        end
        T.changed('UPDATE_MACROS');T.changed('ACTIONBAR_SLOT_CHANGED',0)
    end
    function CreateFrame()
        local f={events={}};T.frames[#T.frames+1]=f
        function f:RegisterEvent(event)self.events[event]=true end
        function f:SetScript(_,handler)self.handler=handler end
        return f
    end
    C_Timer={NewTimer=function(_,fn)
        local timer={Cancel=function(self)self.cancelled=true end}
        T.timers[#T.timers+1]=function()if not timer.cancelled then fn()end end
        return timer
    end}
    assert(loadfile('addon/LycheeTalent/Macros.lua'))('LycheeTalent',A)
    assert(loadfile('addon/LycheeTalent/ActionBars.lua'))('LycheeTalent',A)
    T.B=A.ActionBars
    function T.activate(id,shared,snapshot)
        A.Apply.op={}
        assert(T.B:Restore(snapshot))
        assert(T.B:SaveLayout(T.spec,id,shared,T.B.verified))
        T.B:Spec(T.spec).applied={id=id,spec=T.spec,shared=shared}
        T.B.pendingSpec=nil;A.Apply.op=nil;T.settle()
    end
    function T.body(snapshot,slot)return snapshot.macros[snapshot.slots[slot].id].body end
    return T
end
