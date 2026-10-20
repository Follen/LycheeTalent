local failures=0
local function check(name,fn)
    local ok,err=pcall(fn)
    if ok then print('PASS '..name)
    else failures=failures+1;print('FAIL '..name..': '..tostring(err)) end
end
local function runtime(deferred)
    return assert(loadfile('tests/macro_runtime.lua'))()(deferred or false)
end
local function addMacro(target,slot,ref,body)
    target.slots[slot]={kind='macro',id=ref}
    target.macros[ref]={name='Saved '..ref,icon=134400,body=body}
end
local function owned(T,index,name,body)
    T.native[index]={name=name,icon=134400,body=body}
    local pool=T.A.Macros:Pool();pool[#pool+1]=T.copy(T.native[index])
end

check('missing reused macro cannot save unrelated content',function()
    local T=runtime()
    T.native[1]={name='User',icon=134400,body='/say wanted'};T.slots[1]={kind='macro',id=1}
    local target=assert(T.B:Capture(62));addMacro(target,2,'new','/say new')
    local create=CreateMacro
    CreateMacro=function(...)
        local index=create(...)
        T.native[1]={name='Other user macro',icon=1,body='/say unrelated'}
        return index
    end
    local ok,why,detail=T.B:Restore(target)
    assert(not ok and why=='BARS_MACRO','a missing binding must fail before placing actions')
    assert(T.placements==0 and not T.B.verified and #T.A.Macros:Pool()==0)
    assert(detail.phase=='macro-bind' and detail.rolledBack and T.body(target,1)=='/say wanted')
end)

check('moved owned macros are resolved before each edit',function()
    local T=runtime()
    owned(T,121,'LTAB01','/say old one');owned(T,122,'LTAB02','/say old two')
    T.slots[1]={kind='macro',id=121};T.slots[2]={kind='macro',id=122}
    local target=assert(T.B:Capture(62))
    target.macros['121'].body='/say new one';target.macros['122'].body='/say new two'
    local edit=EditMacro;local moved=false
    EditMacro=function(...)
        local index=edit(...)
        if not moved then
            moved=true;T.native[123]=T.native[122]
            T.native[122]={name='Foreign user macro',icon=1,body='/say leave alone'}
            T.slots[2].id=123
        end
        return index
    end
    assert(T.B:Restore(target),'renumbering must not edit the replacement at the old index')
    assert(T.native[122].name=='Foreign user macro' and T.native[122].body=='/say leave alone')
    assert(T.native[T.slots[2].id].body=='/say new two')
end)

check('changed owned macro is not overwritten',function()
    local T=runtime()
    owned(T,121,'LTAB01','/say old one');owned(T,122,'LTAB02','/say old two')
    T.slots[1]={kind='macro',id=121};T.slots[2]={kind='macro',id=122}
    local target=assert(T.B:Capture(62))
    target.macros['121'].body='/say new one';target.macros['122'].body='/say new two'
    local edit=EditMacro;local changed=false
    EditMacro=function(...)
        local index=edit(...)
        if not changed then changed=true;T.native[122].body='/say external edit' end
        return index
    end
    local ok,why,detail=T.B:Restore(target)
    assert(not ok and why=='BARS_MACRO' and detail.phase=='macro-edit')
    assert(T.native[122].body=='/say external edit' and T.native[121].body=='/say old one')
end)

check('silent delete failure retains ownership and reports incomplete rollback',function()
    local T=runtime()
    local target=assert(T.B:Capture(62));addMacro(target,1,'new','/say new')
    T.failPlace=true;DeleteMacro=function()end
    local ok,why,detail=T.B:Restore(target)
    assert(not ok and why=='BARS_RESTORE' and not detail.rolledBack,'a leftover macro is not a complete rollback')
    assert(T.native[121] and #T.A.Macros:Pool()==1 and T.A.Macros:Owned(T.A.Macros:Scan())[121])
    assert(detail.macroRollback[1].phase=='macro-delete')
end)

check('silent rollback edit does not falsify the pool record',function()
    local T=runtime()
    owned(T,121,'LTAB01','/say old');T.slots[1]={kind='macro',id=121}
    local target=assert(T.B:Capture(62));target.macros['121'].body='/say new'
    target.slots[2]={kind='item',id=999}
    local edit=EditMacro;local calls=0
    EditMacro=function(...)
        calls=calls+1;if calls==1 then return edit(...) end
    end
    T.failPlace=true
    local ok,_,detail=T.B:Restore(target)
    assert(not ok and not detail.rolledBack)
    assert(T.native[121].body=='/say new' and T.A.Macros:Pool()[1].body=='/say new','retain the last confirmed native content')
    assert(T.A.Macros:Owned(T.A.Macros:Scan())[121] and detail.macroRollback[1].phase=='macro-edit')
end)

check('macro changes during action placement roll back the action slots',function()
    local T=runtime()
    T.native[1]={name='User',icon=134400,body='/say wanted'};T.slots[1]={kind='macro',id=1}
    local target=assert(T.B:Capture(62));T.slots[1]={kind='spell',id=100,sub='spell'}
    local place=PlaceAction
    PlaceAction=function(slot)
        place(slot);T.native[1].body='/say changed during placement'
    end
    local ok,why,detail=T.B:Restore(target)
    assert(not ok and why=='BARS_MACRO','post-placement macro content must be verified')
    assert(detail.phase=='macro-verify' and detail.slot==1 and detail.rolledBack)
    assert(T.slots[1].kind=='spell' and T.slots[1].id==100 and not T.B.verified)
    assert(T.body(target,1)=='/say wanted' and T.body(T.B.recovery.requested,1)=='/say wanted')
end)

check('creation sorting keeps existing and newly created bindings correct',function()
    local T=runtime()
    T.native[121]={name='Z user macro',icon=134400,body='/say user'};T.slots[1]={kind='macro',id=121}
    local target=assert(T.B:Capture(62));addMacro(target,2,'newA','/say A');addMacro(target,3,'newB','/say B')
    local create=CreateMacro
    CreateMacro=function(name,icon,body,character)
        local newIndex=create(name,icon,body,character);local added=T.native[newIndex]
        local macros,actions={},{}
        for index=121,150 do if T.native[index] then macros[#macros+1]=T.native[index] end end
        for slot,entry in pairs(T.slots)do if entry.kind=='macro' then actions[slot]=T.native[entry.id] end end
        table.sort(macros,function(a,b)return a.name<b.name end)
        for index=121,150 do T.native[index]=nil end
        for n,macro in ipairs(macros)do
            local index=120+n;T.native[index]=macro
            for slot,old in pairs(actions)do if old==macro then T.slots[slot].id=index end end
            if macro==added then newIndex=index end
        end
        return newIndex
    end
    assert(T.B:Restore(target))
    assert(T.slots[1].id==123 and T.native[123].body=='/say user')
    assert(T.native[T.slots[2].id].body=='/say A' and T.native[T.slots[3].id].body=='/say B')
end)

check('an API exception after creation cleans up its side effect',function()
    local T=runtime()
    local target=assert(T.B:Capture(62));addMacro(target,1,'new','/say new')
    local create=CreateMacro
    CreateMacro=function(...)create(...);error('injected failure after creation')end
    local ok,why,detail=T.B:Restore(target)
    assert(not ok and why=='BARS_MACRO' and detail.phase=='macro-create' and detail.rolledBack)
    assert(not T.native[121] and #T.A.Macros:Pool()==0 and T.placements==0)
end)

check('a rejected edit needs no second edit to roll back unchanged content',function()
    local T=runtime()
    owned(T,121,'LTAB01','/say old');T.slots[1]={kind='macro',id=121}
    local target=assert(T.B:Capture(62));target.macros['121'].body='/say new'
    local calls=0;EditMacro=function()calls=calls+1;error('injected rejected edit')end
    local ok,why,detail=T.B:Restore(target)
    assert(not ok and why=='BARS_MACRO' and detail.rolledBack and calls==1)
    assert(T.native[121].body=='/say old' and T.A.Macros:Pool()[1].body=='/say old')
end)

check('delayed events cannot save a partially rolled back macro into SV',function()
    local T=runtime(true)
    owned(T,121,'LTAB01','/say old');T.slots[1]={kind='macro',id=121}
    local before=assert(T.B:Capture(62));assert(T.B:SeedDefault(62,before,'test'))
    T.B:Spec(62).applied={id='old',spec=62,shared=true};T.B:Init()
    local target=T.copy(before);target.macros['121'].body='/say new';target.slots[2]={kind='item',id=999}
    local edit=EditMacro;local calls=0
    EditMacro=function(...)calls=calls+1;if calls==1 then return edit(...) end end
    T.A.Apply.op={};T.failPlace=true
    local ok,_,detail=T.B:Restore(target);T.A.Apply.op=nil;T.settle()
    assert(not ok and not detail.rolledBack)
    assert(T.B.pendingSpec==62 and T.B.resumeFailed,'incomplete restoration waits for an explicit retry')
    assert(T.body(T.B:Get(62,nil,true),1)=='/say old','keep the saved layout until a restore succeeds')
    EditMacro=edit
    assert(T.B:Restore(before));T.settle()
    EditMacro(121,nil,nil,'/say manual edit');T.settle()
    assert(T.body(T.B:Get(62,nil,true),1)=='/say manual edit','normal observation resumes after successful recovery')
end)

assert(failures==0,tostring(failures)..' macro transaction regressions failed')
