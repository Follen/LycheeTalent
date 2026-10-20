local _, A = ...
local M = {}
A.Macros=M
local function copy(value)
    local out={};for k,v in pairs(value) do out[k]=type(v)=="table" and copy(v) or v end;return out
end
local function secret(value) return issecretvalue and issecretvalue(value) end
function M:Limits()
    local limits=Constants and Constants.MacroConsts or {}
    return limits.MAX_ACCOUNT_MACROS or MAX_ACCOUNT_MACROS or 120,
        limits.MAX_CHARACTER_MACROS or MAX_CHARACTER_MACROS or 30
end
function M:Read(index)
    local name,icon,body=GetMacroInfo(index)
    if secret(name) or secret(icon) or secret(body) or type(name)~="string" then return end
    body=body or ""
    if type(body)~="string" then return end
    if C_Macro and C_Macro.GetSelectedMacroIcon then icon=C_Macro.GetSelectedMacroIcon(index) or icon end
    if secret(icon) then return end
    return {name=name,icon=icon,body=body}
end
function M:Scan()
    local out={};local account,character=self:Limits()
    for index=1,account+character do out[index]=self:Read(index) end
    return out
end
function M:Same(a,b,ignoreName)
    -- Final line feeds can differ between saved and native macro bodies.
    -- Compare those as the same commands without changing the saved text.
    return a and b and (ignoreName or a.name==b.name) and a.icon==b.icon
        and (a.body==b.body or a.body:gsub("\n+$","")==b.body:gsub("\n+$",""))
end
function M:Named(native,name)
    local found
    for index,macro in pairs(native) do
        if macro.name==name then if found then return nil,"ambiguous" end;found=index end
    end
    return found
end
function M:Pool()
    local char=A.Store.character
    char.macroPool=char.macroPool or {}
    return char.macroPool
end
function M:Owned(native)
    local out={}
    for _,record in ipairs(self:Pool()) do
        local index=self:Named(native,record.name)
        if index and self:Same(native[index],record) then out[index]=record end
    end
    return out
end
-- Layout references are local to the snapshot. Native indices are bindings,
-- never the saved macro's identity or the source of its body during restore.
function M:Pack(snapshot,native)
    snapshot.version=2;snapshot.macros={};snapshot.bindings={}
    native=native or self:Scan()
    for _,entry in ipairs(snapshot.slots) do
        if entry.kind=="macro" then
            local index=entry.id;local macro=native[index]
            if not macro then return nil,"BARS_MACRO_READ" end
            local ref=tostring(index)
            snapshot.macros[ref]=copy(macro)
            snapshot.bindings[ref]={index=index,native=copy(macro)}
            entry.id=ref;entry.sub=nil
        end
    end
    return snapshot
end
function M:Plan(snapshot,protected)
    local native=self:Scan();local owned=self:Owned(native)
    local plan={bindings={},existing={},writes={},native=native};local used={}
    local refs,seen={},{}
    for _,entry in ipairs(snapshot.slots) do
        if entry.kind=="macro" and not seen[entry.id] then seen[entry.id]=true;refs[#refs+1]=entry.id end
    end
    table.sort(refs)
    for _,ref in ipairs(refs) do
        local macro=snapshot.macros[ref];local found
        local binding=snapshot.bindings and snapshot.bindings[ref]
        if binding and self:Same(macro,native[binding.index],owned[binding.index]~=nil) then found=binding.index end
        for index,value in pairs(native) do
            if not found and self:Same(macro,value,owned[index]~=nil) then found=index end
        end
        if found then plan.bindings[ref]=found;plan.existing[ref]=native[found];used[found]=true end
    end
    local account,limit=self:Limits();local count=0
    for index in pairs(native) do if index>account then count=count+1 end end
    local reserved={};for _,value in pairs(native) do reserved[value.name]=true end
    for _,ref in ipairs(refs) do
        if not plan.bindings[ref] then
            local macro=snapshot.macros[ref];local shared
            for _,write in ipairs(plan.writes) do if self:Same(macro,write.macro,true) then shared=write;break end end
            if shared then shared.refs[#shared.refs+1]=ref
            else
                local index
                for candidate in pairs(owned) do
                    if not used[candidate] and not (protected and protected[candidate]) and (not index or candidate<index) then index=candidate end
                end
                local name=index and native[index].name
                if index then used[index]=true
                else
                    if count>=limit then return nil,"BARS_MACRO_CAPACITY" end
                    count=count+1
                    local n=1;repeat name=string.format("LTAB%02d",n);n=n+1 until not reserved[name]
                    reserved[name]=true
                end
                plan.writes[#plan.writes+1]={index=index,name=name,macro=macro,refs={ref},record=index and owned[index]}
            end
        end
    end
    return plan
end
local function failure(phase,name,index,reason)
    return nil,"BARS_MACRO",{phase=phase,macro=name,index=index,reason=reason}
end
function M:Execute(plan)
    plan.undo={}
    local native=self:Scan()
    for _,write in ipairs(plan.writes) do
        -- A preceding native call can renumber macros. Never edit a replacement
        -- at the planned index or reclaim a managed macro changed elsewhere.
        local index,ambiguous=self:Named(native,write.name)
        local phase=write.index and "macro-edit" or "macro-create"
        if write.index then
            if not index or not self:Same(native[index],plan.native[write.index]) then
                return failure(phase,write.name,index,ambiguous or (index and "changed" or "missing"))
            end
        elseif index or ambiguous then return failure(phase,write.name,index,"name-in-use") end
        local undo={name=write.name,before=index and copy(native[index]),record=write.record}
        plan.undo[#plan.undo+1]=undo
        local ok,err=pcall(function()
            if index then return EditMacro(index,write.name,write.macro.icon,write.macro.body) end
            return CreateMacro(write.name,write.macro.icon,write.macro.body,true)
        end)
        native=self:Scan()
        index,ambiguous=self:Named(native,write.name)
        if index then
            undo.after=copy(native[index])
            -- A native call may mutate and then throw. Track the created macro
            -- so failed cleanup cannot leave an unregistered execution slot.
            if not undo.record then
                undo.record={};self:Pool()[#self:Pool()+1]=undo.record;undo.created=true
            end
            for k,v in pairs(native[index]) do undo.record[k]=v end
        end
        if not ok or not index or not self:Same(native[index],write.macro,true) then
            return failure(phase,write.name,index,not ok and tostring(err):sub(1,240) or ambiguous or (index and "content-mismatch" or "missing"))
        end
        for _,ref in ipairs(write.refs) do plan.bindings[ref]=index end
    end
    -- Creation may renumber native indices. Resolve all bindings again after
    -- the final write, including unchanged user macros selected by the plan.
    for ref,expected in pairs(plan.existing) do
        local index=plan.bindings[ref]
        if not self:Same(native[index],expected) then
            index=nil
            for candidate,value in pairs(native) do
                if self:Same(value,expected) then index=candidate;break end
            end
        end
        if not index then return failure("macro-bind",expected.name,plan.bindings[ref],"missing") end
        plan.bindings[ref]=index
    end
    for _,write in ipairs(plan.writes) do
        local index,ambiguous=self:Named(native,write.name)
        if not index or not self:Same(native[index],write.macro,true) then
            return failure("macro-bind",write.name,index,ambiguous or (index and "content-mismatch" or "missing"))
        end
        for _,ref in ipairs(write.refs) do plan.bindings[ref]=index end
    end
    return true
end
function M:PreserveNames(snapshot,previous)
    for ref,binding in pairs(snapshot.bindings or {}) do
        for oldRef,old in pairs(previous and previous.bindings or {}) do
            if binding.index==old.index and binding.native.name==old.native.name then
                snapshot.macros[ref].name=previous.macros[oldRef].name;break
            end
        end
    end
    return snapshot
end
function M:Rollback(plan)
    local failures={}
    for n=#(plan.undo or {}),1,-1 do
        local undo=plan.undo[n]
        local called,restored,reason=pcall(function()
            local native=self:Scan();local index,ambiguous=self:Named(native,undo.name)
            if ambiguous then return nil,ambiguous end
            if undo.before then
                if not index then return nil,"missing" end
                if not self:Same(native[index],undo.before) then
                    if not self:Same(native[index],undo.after) then return nil,"changed" end
                    local ok,err=pcall(EditMacro,index,undo.before.name,undo.before.icon,undo.before.body)
                    native=self:Scan();index,ambiguous=self:Named(native,undo.name)
                    if not index or not self:Same(native[index],undo.before) then
                        return nil,not ok and tostring(err):sub(1,240) or ambiguous or "content-mismatch"
                    end
                end
                for k,v in pairs(native[index]) do undo.record[k]=v end
            elseif index then
                if not self:Same(native[index],undo.after) then return nil,"changed" end
                local ok,err=pcall(DeleteMacro,index)
                index,ambiguous=self:Named(self:Scan(),undo.name)
                if index or ambiguous then return nil,not ok and tostring(err):sub(1,240) or ambiguous or "not-deleted" end
            end
            return true
        end)
        if called and restored and undo.created then
            local pool=self:Pool();for i=#pool,1,-1 do if pool[i]==undo.record then table.remove(pool,i) end end
        end
        if not called or not restored then
            failures[#failures+1]={phase=undo.before and "macro-edit" or "macro-delete",macro=undo.name,
                reason=called and reason or tostring(restored):sub(1,240)}
        end
    end
    return #failures==0,#failures>0 and failures or nil
end
function M:Physical(snapshot,bindings)
    local out=copy(snapshot)
    out.version=1;out.macros=nil;out.bindings=nil
    for _,entry in ipairs(out.slots) do
        if entry.kind=="macro" then entry.id=bindings[entry.id];entry.sub=nil end
    end
    return out
end
-- UPDATE_MACROS has no index argument. Match unchanged definitions first so a
-- deletion/rename that renumbers the macro table cannot edit an unrelated macro.
function M:Changes(previous,current)
    local mapping,used={},{}
    for index,old in pairs(previous) do
        if self:Same(old,current[index]) then mapping[index]=index;used[index]=true end
    end
    for index,old in pairs(previous) do
        if not mapping[index] then
            for candidate,value in pairs(current) do
                if not used[candidate] and self:Same(old,value) then mapping[index]=candidate;used[candidate]=true;break end
            end
        end
    end
    local account=self:Limits()
    for _,character in ipairs({false,true}) do
        local oldLeft,newLeft={},{}
        for index in pairs(previous) do if (index>account)==character and not mapping[index] then oldLeft[#oldLeft+1]=index end end
        for index in pairs(current) do if (index>account)==character and not used[index] then newLeft[#newLeft+1]=index end end
        if #oldLeft==1 and #newLeft==1 then mapping[oldLeft[1]]=newLeft[1]
        else
            for _,index in ipairs(oldLeft) do
                local candidate=self:Named(current,previous[index].name)
                if candidate and not used[candidate] then mapping[index]=candidate;used[candidate]=true end
            end
        end
    end
    return mapping
end
function M:Refresh(snapshot,previous,current)
    local mapping=self:Changes(previous,current);local owned=self:Owned(previous)
    for ref,binding in pairs(snapshot.bindings or {}) do
        local index=mapping[binding.index]
        if index and self:Same(binding.native,previous[binding.index]) then
            local macro=current[index];local saved=snapshot.macros[ref]
            local name=owned[binding.index] and macro.name==binding.native.name and saved.name or macro.name
            snapshot.macros[ref]={name=name,icon=macro.icon,body=macro.body}
            snapshot.bindings[ref]={index=index,native=copy(macro)}
        end
    end
    return mapping
end
function M:RefreshPool(previous,current,mapping)
    for index,record in pairs(self:Owned(previous)) do
        local nextIndex=mapping[index]
        if nextIndex then for k,v in pairs(current[nextIndex]) do record[k]=v end end
    end
end
M.Copy=copy
