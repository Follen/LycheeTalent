local _,A=...
local I={}
A.TalentEx=I

function I:Source()
    local _,class=UnitClass("player")
    local index=C_SpecializationInfo.GetSpecialization()
    local db=TalentLoadoutEx
    if type(db)~="table" then return nil,"TEX_UNAVAILABLE" end
    local specs=db[class]
    local source=type(specs)=="table" and specs[index]
    if type(source)~="table" then return nil,"TEX_EMPTY" end
    return source
end

-- Read the external SavedVariables without calling Talent EX's mutating helpers.
-- Its specialization keys are indices, not specialization IDs; group rows lack text.
function I:Import()
    if InCombatLockdown() then return nil,"COMBAT" end
    if A.Apply.op then return nil,"APPLY_BUSY" end
    if A.Store.readonly then return nil,"SCHEMA" end
    local source,why=self:Source()
    if not source then return nil,why end
    local keys={}
    for key in pairs(source) do
        if type(key)=="number" and key>0 and key%1==0 then keys[#keys+1]=key end
    end
    if #keys>10000 then return nil,"CAPACITY" end
    table.sort(keys)
    local spec=A:GetSpec()
    local known={}
    local function key(name,code)return name.."\0"..code end
    for _,b in ipairs(A.Store.builds) do
        if type(b)=="table" and b.specID==spec and type(b.name)=="string" and type(b.code)=="string" then
            known[key(b.name,b.code:gsub("%s",""))]=true
        end
    end
    local result={imported=0,duplicate=0,invalid=0,groups=0,remaining=0}
    for position,index in ipairs(keys) do
        local entry=source[index]
        if type(entry)=="table" and entry.text==nil then
            result.groups=result.groups+1
        elseif type(entry)~="table" or entry.isLegacy or type(entry.text)~="string" then
            result.invalid=result.invalid+1
        else
            local code,codeSpec=A.Talents:Validate(entry.text)
            local name=type(entry.name)=="string" and entry.name:match("^%s*(.-)%s*$") or ""
            if not code or codeSpec~=spec or name=="" or #name>160 then
                result.invalid=result.invalid+1
            elseif known[key(name,code)] then
                result.duplicate=result.duplicate+1
            else
                local b,reason=A.Store:Save(name,code,"mythic","",spec)
                if not b then
                    result.reason=reason;result.remaining=#keys-position+1;break
                end
                if type(entry.icon)=="number" and entry.icon>0 and entry.icon%1==0 then b.icon=entry.icon
                elseif type(entry.icon)=="string" and #entry.icon<=512 then b.icon=entry.icon end
                known[key(name,code)]=true
                result.imported=result.imported+1;result.firstID=result.firstID or b.id
            end
        end
    end
    return result
end
