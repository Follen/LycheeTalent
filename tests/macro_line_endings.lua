local function runtime()
    local T=assert(loadfile('tests/macro_runtime.lua'))()(false)
    -- The captured BARS_MACRO recovery has saved bodies without a final LF
    -- and otherwise identical native bodies with one. Model that write result.
    local create,edit=CreateMacro,EditMacro
    local function nativeBody(body)
        return body:sub(-1)=='\n' and body or body..'\n'
    end
    CreateMacro=function(name,icon,body,character)return create(name,icon,nativeBody(body),character)end
    EditMacro=function(index,name,icon,body)return edit(index,name,icon,nativeBody(body))end
    T.native[121]={name='Saved',icon=134400,body='/cast Alpha\n'}
    T.slots[1]={kind='macro',id=121}
    local target=assert(T.B:Capture(62))
    target.macros['121'].body='/cast Alpha'
    target.bindings['121'].native.body='/cast Alpha'
    return T,target
end

-- One macro and one final newline are enough to reproduce BARS_MACRO.
local T,target=runtime()
local ok,why=T.B:Restore(target)
assert(ok,'matching saved macro should restore; got '..tostring(why))
assert(T.writes==0 and T.slots[1].id==121,'a final newline must not allocate a duplicate macro')
assert(T.body(T.B.verified,1)=='/cast Alpha','keep the original saved text')

T,target=runtime()
T.native[121]=nil;T.slots[1]=nil
assert(T.B:Restore(target),'creation must accept the same body with a final newline')
assert(T.native[T.slots[1].id].body=='/cast Alpha\n' and #T.A.Store.character.macroPool==1)
local alternate=T.copy(target);alternate.macros['121'].body='/cast Beta'
assert(T.B:Restore(alternate),'pool edits must accept the same body with a final newline')
assert(T.native[T.slots[1].id].body=='/cast Beta\n' and #T.A.Store.character.macroPool==1)

-- A command change is still a failure and must roll back both text and slots.
local edit=EditMacro
local corrupt=true
EditMacro=function(index,name,icon,body)
    if corrupt then corrupt=false;body='/cast Wrong' end
    return edit(index,name,icon,body)
end
local restored,reason,detail=T.B:Restore(target)
assert(not restored and reason=='BARS_MACRO','different commands must not pass verification')
assert(detail and detail.rolledBack and T.native[T.slots[1].id].body=='/cast Beta\n','a real mismatch must restore the previous text')
assert(T.A.Macros:Same({name='a',icon=1,body='/cast Alpha\n\n'},{name='a',icon=1,body='/cast Alpha'}))
assert(not T.A.Macros:Same({name='a',icon=1,body='/cast Alpha'},{name='a',icon=1,body='/cast  Alpha'}),'do not normalize command text')
assert(not T.A.Macros:Same({name='a',icon=1,body='/cast Alpha'},{name='a',icon=2,body='/cast Alpha\n'}),'icon differences remain significant')
print('PASS macro final newlines: reuse, creation, pool edits, saved text and real mismatch detection')
