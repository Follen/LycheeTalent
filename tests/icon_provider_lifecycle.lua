-- Feed the pinned Blizzard IconDataProvider.lua source on stdin.
-- This exercises its actual Lua lifecycle with synthetic game API responses.
local source = io.read("*a"):gsub("^\239\187\191", "")
assert(source:find("IconDataProviderMixin:Release", 1, true), "provider source required on stdin")

local refreshes, clears = 0, 0
local types = { Spell = 1, Item = 2 }
local env = setmetatable({
    IconDataProviderIconType = types,
    EnumUtil = { MakeEnum = function() return types end },
    GetValuesArray = function(t) return { t.Spell, t.Item } end,
    GetKeysArray = function() return {} end,
    GetLooseMacroIcons = function(out) refreshes = refreshes + 1; out[1] = 111 end,
    GetLooseMacroItemIcons = function(out) out[1] = 222 end,
    GetMacroIcons = function(out) out[2] = 333 end,
    GetMacroItemIcons = function(out) out[2] = 444 end,
    collectgarbage = function() clears = clears + 1 end,
    tContains = function(t, value)
        for _, candidate in ipairs(t) do if candidate == value then return true end end
        return false
    end,
}, { __index = _G })
local chunk = assert(loadstring(source, "@pinned/IconDataProvider.lua"))
setfenv(chunk, env)
chunk()

local function create()
    local provider = setmetatable({}, { __index = env.IconDataProviderMixin })
    provider:Init(env.IconDataProviderExtraType.Spellbook)
    return provider
end

local first = create()
assert(first:GetNumIcons() == 5 and refreshes == 1 and clears == 0)
local second = create()
assert(second:GetNumIcons() == 5 and refreshes == 1 and clears == 0,
    "active providers share one base catalog")
first:Release()
first = nil
assert(second:GetNumIcons() == 5 and clears == 0,
    "releasing one of two providers keeps the shared catalog")
second:Release()
second = nil
assert(clears == 1, "last release clears the catalog and invokes global GC")

local function openPicker(picker)
    if not picker.provider then
        picker.provider = create()
        picker.provider:SetIconTypes(picker.filter and { picker.filter } or nil)
    end
    local count = picker.provider:GetNumIcons()
    picker.page = math.max(1, math.min(math.ceil(count / 30), picker.page))
end
local function hidePicker(picker)
    if picker.provider then
        picker.provider:Release()
        picker.provider = nil
    end
end

local picker = { filter = types.Item, page = 3 }
for i = 1, 100 do
    openPicker(picker)
    assert(picker.provider:GetNumIcons() == 3 and picker.page == 1,
        "reopen restores filter and clamps the page")
    hidePicker(picker)
    hidePicker(picker) -- parent/child hide paths must not release twice
    assert(picker.provider == nil and clears == i + 1)
end
assert(refreshes == 101 and clears == 101,
    "each reopen rebuilds once and each final hide clears once")
print("PASS pinned provider lifecycle: 101 builds, 101 final releases, 101 GC calls")
