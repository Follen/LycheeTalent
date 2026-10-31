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
-- Native references are shared across layouts. Backups never become writes.
local function scope(index) return index<=M:Limits() end
local function unique(native,predicate)
    local found
    for index,macro in pairs(native) do
        if predicate(macro,index) then if found then return nil end;found=index end
    end
    return found
end
function M:Changes(previous,current,exactOnly)
    local mapping,used={},{}
    for index,old in pairs(previous) do
        if self:Same(old,current[index]) then mapping[index]=index;used[index]=true end
    end
    for index,old in pairs(previous) do
        if not mapping[index] then
            local candidate=unique(current,function(value,id)
                return not used[id] and scope(index)==scope(id) and self:Same(old,value)
            end)
            if candidate then mapping[index]=candidate;used[candidate]=true end
        end
    end
    if not exactOnly then
        for index,old in pairs(previous) do
            if not mapping[index] and self:Named(previous,old.name)==index then
                local candidate=self:Named(current,old.name)
                if candidate and not used[candidate] and scope(index)==scope(candidate) then
                    mapping[index]=candidate;used[candidate]=true
                end
            end
        end
        for index,old in pairs(previous) do
            if not mapping[index] then
                local function content(value,id)
                    return scope(index)==scope(id) and self:Same(old,value,true)
                end
                local candidate=unique(current,function(value,id)return not used[id] and content(value,id)end)
                if candidate and unique(previous,content)==index then mapping[index]=candidate;used[candidate]=true end
            end
        end
    end
    return mapping
end
function M:Sync(native,exactOnly)
    -- Most UPDATE_MACROS notifications carry identical content. Scan native
    -- scalars every time, but leave stable records and saved layouts in place.
    local unchanged,count=true,0
    for _,record in pairs(self.registry.records) do
        if record.index then
            local current,old=native[record.index],record.native
            if not current or not old or current.name~=old.name or current.icon~=old.icon or current.body~=old.body then
                unchanged=false;break
            end
            count=count+1
        end
    end
    if unchanged then
        for _ in pairs(native) do count=count-1 end
        if count==0 then return false end
    end
    local previous={}
    for _,record in pairs(self.registry.records) do if record.index then previous[record.index]=record.native end end
    local mapping=self:Changes(previous,native,exactOnly)
    local assigned={}
    for _,record in pairs(self.registry.records) do
        local index=record.index and mapping[record.index]
        record.index=index
        if index then record.native=copy(native[index]);assigned[index]=true end
    end
    for index,macro in pairs(native) do
        if not assigned[index] then
            local id=self.registry.nextID+1;self.registry.nextID=id
            self.registry.records[tostring(id)]={index=index,native=copy(macro)}
        end
    end
    self.revision=(self.revision or 0)+1
    return true
end
function M:Initialize()
    local char=A.Store.character
    if self.character==char then return end
    self.character=char
    char.nativeMacros=char.nativeMacros or {nextID=0,records={}}
    self.registry=char.nativeMacros
    -- Across reloads only a complete observed identity can survive.
    self:Sync(self:Scan(),true)
end
function M:Current()
    self:Initialize()
    local native=self:Scan();local changed=self:Sync(native)
    return native,changed
end
function M:Pack(snapshot,native)
    native=native or self:Current()
    self:Initialize()
    snapshot.version=2;snapshot.macros={}
    for _,entry in ipairs(snapshot.slots) do
        if entry.kind=="macro" then
            local index=entry.id;local macro=native[index]
            if not macro then return nil,"BARS_MACRO_READ" end
            local id
            for key,record in pairs(self.registry.records) do if record.index==index then id=key;break end end
            if not id then return nil,"BARS_MACRO_READ" end
            snapshot.macros[id]=copy(macro);snapshot.macros[id].nativeID=id
            entry.id=id;entry.sub=nil
        end
    end
    return snapshot
end
function M:Resolve(macro,native)
    self:Initialize()
    local record=macro.nativeID and self.registry.records[tostring(macro.nativeID)]
    local index=record and record.index
    if index and self:Same(native[index],record.native) then return index end
end
function M:Physical(snapshot,native)
    native=native or self:Current()
    local out=copy(snapshot);out.version=1;out.macros=nil
    local missing={}
    for slot,entry in ipairs(out.slots) do
        if entry.kind=="macro" then
            local macro=snapshot.macros[entry.id]
            local index=self:Resolve(macro,native)
            if index then entry.id=index;entry.sub=nil
            else missing[slot]=copy(macro);out.slots[slot]={kind="unreadableMacro",id=slot} end
        end
    end
    return out,missing
end
function M:Refresh(snapshot)
    for ref,macro in pairs(snapshot.macros or {}) do
        local record=macro.nativeID and self.registry.records[tostring(macro.nativeID)]
        if record and record.index then
            local updated=copy(record.native);updated.nativeID=macro.nativeID
            snapshot.macros[ref]=updated
        end
    end
end
M.Copy=copy
