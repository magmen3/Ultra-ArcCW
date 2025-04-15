-- Used to prevent stack overflow. Set false here so luarefresh clears it
ArcCW.BuffStack = false

ArcCW.ConVar_BuffMults = {
    ["Mult_Damage"] = "arccw_mult_damage",
    ["Mult_DamageMin"] = "arccw_mult_damage",
    ["Mult_DamageNPC"] = "arccw_mult_npcdamage",
    ["Mult_HipDispersion"] = "arccw_mult_hipfire",
    ["Mult_ReloadTime"] = "arccw_mult_reloadtime",
    ["Mult_SightTime"] = "arccw_mult_sighttime",
    ["Mult_RPM"] = "arccw_mult_rpm",
    ["Mult_CycleTime"] = "arccw_mult_rpm",
    ["Mult_Range"] = "arccw_mult_range",
    ["Mult_Recoil"] = "arccw_mult_recoil",
    ["Mult_MoveDispersion"] = "arccw_mult_movedisp",
    ["Mult_AccuracyMOA"] = "arccw_mult_accuracy",
    ["Mult_Penetration"] = "arccw_mult_penetration",
    ["Mult_Sway"] = "arccw_mult_sway",
    ["Mult_MeleeDamage"] = "arccw_mult_meleedamage",
    ["Mult_MeleeTime"] = "arccw_mult_meleetime",
}

ArcCW.ConVar_BuffAdds = {
    ["Add_Sway"] = "arccw_add_sway",
}

ArcCW.ConVar_BuffOverrides = {
    ["Override_ShootWhileSprint"] = "arccw_mult_shootwhilesprinting"
}

SWEP.TickCache_Overrides = {}
SWEP.TickCache_Adds = {}
SWEP.TickCache_Mults = {}
SWEP.TickCache_Hooks = {}
SWEP.TickCache_IsShotgun = nil

SWEP.TickCache_Tick_Overrides = {}
SWEP.TickCache_Tick_Adds = {}
SWEP.TickCache_Tick_Mults = {}

SWEP.AttCache_Hooks = {}

-- debug: enable/disable modified caching
local MODIFIED_CACHE = true
-- print if a variable presumed to never change actually changes (this also happens right after attaching/detaching)
-- only works if MODIFIED_CACHE is false
local VERIFY_MODIFIED_CACHE = false

-- Conditions not listed are are presumed to never change; this is done for optimization purposes
SWEP.ModifiedCache = {}

local custsounds, oldmenu = GetConVar("arccw_cust_sounds"), GetConVar("arccw_oldmenu")

function SWEP:RecalcAllBuffs()
    self.TickCache_Overrides = {}
    self.TickCache_Adds = {}
    self.TickCache_Mults = {}
    self.TickCache_Hooks = {}
    self.TickCache_IsShotgun = nil

    self.TickCache_Tick_Overrides = {}
    self.TickCache_Tick_Adds = {}
    self.TickCache_Tick_Mults = {}

    self.ReferencePosCache = {}

    self.AttCache_Hooks = {}

    self.NextMalfunction = nil

    -- for the customization page
    if CLIENT then
        self.Infos_Stats = nil
        self.Infos_Ballistics = nil
        self.Infos_Breakpoints = nil
    end

    -- this function is not always called right before AdjustAtts
    --self.ModifiedCache = {}
end

function SWEP:GetIsShotgun()
    if self.TickCache_IsShotgun == nil then
        local shotgun = self:GetBuff_Override("Override_IsShotgun")
        if shotgun != nil then
            self.TickCache_IsShotgun = shotgun
        end

        local num = self.Num
        if self.TickCache_IsShotgun == nil and num > 1 then self.TickCache_IsShotgun = true end
    end

    return self.TickCache_IsShotgun
end

function SWEP:GetIsManualAction()
    local manual = self:GetBuff_Override("Override_ManualAction")

    if manual != false then
        manual = manual or self.ManualAction
    end

    -- A manual action gun CAN have automatic firemode, this is intended behavior!!!
    -- It's used for slamfiring
    --[[]
    local mode = self:GetCurrentFiremode().Mode

    if mode != 0 and mode != 1 then
        return false
    end
    ]]

    return manual
end

-- ONE FUNCTION TO RULE THEM ALL
local getmetatable = getmetatable

do
    local numberMeta = getmetatable(0)
    if not numberMeta then
        numberMeta = {MetaName = 'number'}
        debug.setmetatable(0, numberMeta)
    end

    local function isnumber(val)
        return getmetatable(val) == numberMeta
    end

    function SWEP:GetBuff(buff, defaultnil, defaultvar)
        local result = self[buff] or defaultvar
        if !result and defaultnil then
            result = nil
        elseif !result then
            result = 1
        end
    
        result = self:GetBuff_Override("Override_" .. buff, result)
    
        if isnumber(result) then
            result = self:GetBuff_Add("Add_" .. buff) + result
            result = self:GetBuff_Mult("Mult_" .. buff) * result
        end
    
        return result
    end
end

function SWEP:GetBuff_Stat(buff, slot)
    local slottbl = self.Attachments[slot]
    if !slottbl then return end
    local atttbl = ArcCW.AttachmentTable[slottbl.Installed]
    if !atttbl then return end
    local num = slottbl.ToggleNum or 1

    if atttbl.ToggleStats and atttbl.ToggleStats[num] and (atttbl.ToggleStats[num][buff] != nil) then
        return atttbl.ToggleStats[num][buff]
    else
        return atttbl[buff]
    end
end

do
    local function sortBuffHooks(a, b)
        return a[2] >= b[2]
    end

    local blank = function() end

    local functionMeta = getmetatable(blank)
    if not functionMeta then
        functionMeta = {MetaName = 'function'}
        debug.setmetatable(blank, functionMeta)
    end

    local function isfunction(val)
        return getmetatable(val) == functionMeta
    end

    function SWEP:GetBuff_Hook(buff, data, defaultnil)
        -- call through hook function, args = data. return nil to do nothing. return false to prevent thing from happening.
        -- uuugghh
        local buffConcPriority = buff .. "_Priority"
        if !self.AttCache_Hooks[buff] then
            -- self.AttCache_Hooks[buff] = {}
            local buffHooks = {}
            local buffHooksLen = 0

            self.AttCache_Hooks[buff] = buffHooks

            for i, k in ipairs(self.Attachments) do
                if !k.Installed then continue end

                local atttbl = ArcCW.AttachmentTable[k.Installed]

                if !atttbl then continue end

                local tblBuff = atttbl[buff]
                local tglStats = atttbl.ToggleStats
                local tglNum = k.ToggleNum

                if isfunction(tblBuff) then
                    buffHooksLen = buffHooksLen + 1
                    buffHooks[buffHooksLen] = {tblBuff, atttbl[buff .. "_Priority"] or 0}
                elseif tglStats and tglNum and tglStats[tglNum] and isfunction(tglStats[tglNum][buff]) then
                    local toggleNumStats = tglStats[tglNum]

                    buffHooksLen = buffHooksLen + 1
                    buffHooks[buffHooksLen] = {toggleNumStats[buff], toggleNumStats[buff .. "_Priority"] or 0}
                end
            end

            local cfm = self:GetCurrentFiremode()
    
            if cfm and isfunction(cfm[buff]) then
                buffHooksLen = buffHooksLen + 1
                buffHooks[buffHooksLen] = {cfm[buff], cfm[buffConcPriority] or 0}
            end

            local attachmentElements = self.AttachmentElements
            for i, e in ipairs(self:GetActiveElements()) do
                local ele = attachmentElements[e]
    
                if ele and ele[buff] then
                    buffHooksLen = buffHooksLen + 1
                    buffHooks[buffHooksLen] = {ele[buff], ele[buffConcPriority] or 0}
                end
            end

            if isfunction(self[buff]) then
                buffHooksLen = buffHooksLen + 1
                buffHooks[buffHooksLen] = {self[buff], self[buffConcPriority] or 0}
            end

            table.sort(buffHooks, sortBuffHooks)
        end

        local retvalue = nil
        local hooks = self.AttCache_Hooks[buff]
        for i = 1, #hooks do
            local ret = hooks[i][1](self, data)
            if ret ~= nil then
                if ret == false then
                    return
                end
                retvalue = ret
                break
            end
        end

        if retvalue then 
            data = retvalue
        elseif defaultnil then 
            data = nil 
        end

        return hook.Call(buff, nil, self, data) or data
    end
end

function SWEP:GetBuff_Override(buff, default)

    local level = 0
    local current = nil
    local winningslot = nil

    if MODIFIED_CACHE and !self.ModifiedCache[buff] then
        -- ArcCW.ConVar_BuffOverrides[buff] isn't actually implemented??

        if !ArcCW.BuffStack then
            ArcCW.BuffStack = true
            local out = (self:GetBuff_Hook("O_Hook_" .. buff, {buff = buff}) or {})
            current = out.current or current
            winningslot = out.winningslot or winningslot
            ArcCW.BuffStack = false
        end

        return current or default, winningslot
    end

    -- uuugghh WHY I AM DOING THIS
    local buffConcPriority = buff .. "_Priority"

    local buffOverrides = self.TickCache_Overrides[buff]
    if buffOverrides then
        current = buffOverrides[1]
        winningslot = buffOverrides[2]

        local data = {
            buff = buff,
            current = current,
            winningslot = winningslot
        }

        if !ArcCW.BuffStack then
            ArcCW.BuffStack = true

            local out = (self:GetBuff_Hook("O_Hook_" .. buff, data) or {})

            current = out.current or current
            winningslot = out.winningslot or winningslot

            ArcCW.BuffStack = false
        end

        if current == nil then
            return default
        else
            return current, winningslot
        end
    end

    for i, k in ipairs(self.Attachments) do
        if !k.Installed then continue end

        local atttbl = ArcCW.AttachmentTable[k.Installed]

        if !atttbl then continue end

        if atttbl[buff] != nil then
            local pri = atttbl[buffConcPriority] or 1
            if level == 0 or (pri > level) then
                current = atttbl[buff]
                level = pri
                winningslot = i
            end
        end
        if atttbl.ToggleStats and k.ToggleNum then
            local toggleNumStats = atttbl.ToggleStats[k.ToggleNum]
            if toggleNumStats and toggleNumStats[buff] then
                local pri = toggleNumStats[buffConcPriority] or 1
                if level == 0 or (pri > level) then
                    current = toggleNumStats[buff]
                    level = pri
                    winningslot = i
                end
            end
        end
    end

    if !ArcCW.BuffStack then
        ArcCW.BuffStack = true

        local cfm = self:GetCurrentFiremode()

        if cfm and cfm[buff] != nil then
            local pri = cfm[buffConcPriority] or 1
            if level == 0 or (pri > level) then
                current = cfm[buff]
                level = pri
            end
        end

        ArcCW.BuffStack = false
    end

    if !ArcCW.BuffStack then
        ArcCW.BuffStack = true

        local attachmentElements = self.AttachmentElements
        for i, e in ipairs(self:GetActiveElements()) do
            local ele = attachmentElements[e]

            if ele and ele[buff] != nil then
                local pri = ele[buffConcPriority] or 1
                if level == 0 or (pri > level) then
                    current = ele[buff]
                    level = pri
                    winningslot = i
                end
            end
        end

        ArcCW.BuffStack = false
    end

    local selfBuff = self[buff]
    if selfBuff != nil then
        local pri = self[buffConcPriority] or 1
        if level == 0 or (pri > level) then
            current = selfBuff
            level = pri
        end
    end

    self.TickCache_Overrides[buff] = {current, winningslot}

    if VERIFY_MODIFIED_CACHE and !self.ModifiedCache[buff] and current != nil then
        print("ArcCW: Presumed non-changing buff '" .. buff .. "' is modified (" .. tostring(current) .. ")!")
    end

    if !ArcCW.BuffStack then
        ArcCW.BuffStack = true

        local data = {
            buff = buff,
            current = current,
            winningslot = winningslot
        }
        current = (self:GetBuff_Hook("O_Hook_" .. buff, data) or {}).current or current
        ArcCW.BuffStack = false
    end

    if current == nil then
        current = default
    end

    return current, winningslot
end


local cvarGetFloat = FindMetaTable('ConVar').GetFloat

do
    -- to be modified
    local overrideData = {
        buff = true,
        mult = true,
    }

    function SWEP:GetBuff_Mult(buff)
        local mult = 1

        if MODIFIED_CACHE and !self.ModifiedCache[buff] then
            if !ArcCW.BuffStack then
                ArcCW.BuffStack = true
                mult = (self:GetBuff_Hook("M_Hook_" .. buff, {buff = buff, mult = 1}) or {}).mult or mult
                ArcCW.BuffStack = false
            end
            if ArcCW.ConVar_BuffMults[buff] then
                if buff == "Mult_CycleTime" then
                    mult = mult / cvarGetFloat(GetConVar(ArcCW.ConVar_BuffMults[buff]))
                else
                    mult = mult * cvarGetFloat(GetConVar(ArcCW.ConVar_BuffMults[buff]))
                end
            end
            return mult
        end

        if self.TickCache_Mults[buff] then
            mult = self.TickCache_Mults[buff]

            overrideData.buff = buff
            overrideData.mult = mult

            if !ArcCW.BuffStack then
                ArcCW.BuffStack = true

                mult = (self:GetBuff_Hook("M_Hook_" .. buff, overrideData) or {}).mult or mult

                ArcCW.BuffStack = false
            end

            if ArcCW.ConVar_BuffMults[buff] then
                if buff == "Mult_CycleTime" then
                    mult = mult / cvarGetFloat(GetConVar(ArcCW.ConVar_BuffMults[buff]))
                else
                    mult = mult * cvarGetFloat(GetConVar(ArcCW.ConVar_BuffMults[buff]))
                end
            end

            return mult
        end

        for i, k in ipairs(self.Attachments) do
            if !k.Installed then continue end

            local atttbl = ArcCW.AttachmentTable[k.Installed]

            if atttbl[buff] then
                mult = mult * atttbl[buff]
            end

            if atttbl.ToggleStats and k.ToggleNum and atttbl.ToggleStats[k.ToggleNum] and atttbl.ToggleStats[k.ToggleNum][buff] then
                mult = mult * atttbl.ToggleStats[k.ToggleNum][buff]
            end
        end

        local cfm = self:GetCurrentFiremode()

        if cfm and cfm[buff] then
            mult = mult * cfm[buff]
        end

        local selfBuff = self[buff]
        if selfBuff then
            mult = mult * selfBuff
        end

        local attachmentElements = self.AttachmentElements
        for i, e in ipairs(self:GetActiveElements()) do
            local ele = attachmentElements[e]
    
            if ele and ele[buff] then
                mult = mult * ele[buff]
            end
        end

        self.TickCache_Mults[buff] = mult

        if VERIFY_MODIFIED_CACHE and !self.ModifiedCache[buff] and mult != 1 then
            print("ArcCW: Presumed non-changing buff '" .. buff .. "' is modified (" .. tostring(mult) .. ")!")
        end

        if ArcCW.ConVar_BuffMults[buff] then
            if buff == "Mult_CycleTime" then
                mult = mult / cvarGetFloat(GetConVar(ArcCW.ConVar_BuffMults[buff]))
            else
                mult = mult * cvarGetFloat(GetConVar(ArcCW.ConVar_BuffMults[buff]))
            end
        end

        overrideData.buff = buff
        overrideData.mult = mult

        if !ArcCW.BuffStack then
            ArcCW.BuffStack = true
            mult = (self:GetBuff_Hook("M_Hook_" .. buff, overrideData) or {}).mult or mult
            ArcCW.BuffStack = false
        end
    
        return mult
    end
end

do
    -- to be modified
    local overrideData = {
        buff = true,
        add = true,
    }

    function SWEP:GetBuff_Add(buff)
        local add = 0

        if MODIFIED_CACHE and !self.ModifiedCache[buff] then
            if !ArcCW.BuffStack then
                ArcCW.BuffStack = true

                overrideData.buff = buff
                overrideData.add = 0

                add = (self:GetBuff_Hook("A_Hook_" .. buff, overrideData) or {}).add or add
                ArcCW.BuffStack = false
            end
            if ArcCW.ConVar_BuffAdds[buff] then
                add = add + cvarGetFloat(GetConVar(ArcCW.ConVar_BuffAdds[buff]))
            end
            return add
        end

        if self.TickCache_Adds[buff] then
            add = self.TickCache_Adds[buff]

            if !ArcCW.BuffStack then
                ArcCW.BuffStack = true

                overrideData.buff = buff
                overrideData.add = add
                add = (self:GetBuff_Hook("A_Hook_" .. buff, overrideData) or {}).add or add
                ArcCW.BuffStack = false
            end

            if ArcCW.ConVar_BuffAdds[buff] then
                add = add + cvarGetFloat(GetConVar(ArcCW.ConVar_BuffAdds[buff]))
            end

            return add
        end

        for i, k in ipairs(self.Attachments) do
            if !k.Installed then continue end

            local atttbl = ArcCW.AttachmentTable[k.Installed]

            if atttbl[buff] then
                add = add + atttbl[buff]
            end

            if atttbl.ToggleStats and k.ToggleNum and atttbl.ToggleStats[k.ToggleNum] and atttbl.ToggleStats[k.ToggleNum][buff] then
                add = add + atttbl.ToggleStats[k.ToggleNum][buff]
            end
        end

        local cfm = self:GetCurrentFiremode()
    
        if cfm and cfm[buff] then
            add = add + cfm[buff]
        end

        local attachmentElements = self.AttachmentElements
        for i, e in ipairs(self:GetActiveElements()) do
            local ele = attachmentElements[e]
    
            if ele and ele[buff] then
                add = add + ele[buff]
            end
        end

        self.TickCache_Adds[buff] = add

        if VERIFY_MODIFIED_CACHE and !self.ModifiedCache[buff] and add != 0 then
            print("ArcCW: Presumed non-changing buff '" .. buff .. "' is modified (" .. tostring(add) .. ")!")
        end

        if ArcCW.ConVar_BuffAdds[buff] then
            add = add + cvarGetFloat(GetConVar(ArcCW.ConVar_BuffAdds[buff]))
        end

        if !ArcCW.BuffStack then
            ArcCW.BuffStack = true

            overrideData.buff = buff
            overrideData.add = add

            add = (self:GetBuff_Hook("A_Hook_" .. buff, overrideData) or {}).add or add
            ArcCW.BuffStack = false
        end
        return add
    end
end

SWEP.ActiveElementCache = nil

function SWEP:GetActiveElements(recache)
    if self.ActiveElementCache and !recache then return self.ActiveElementCache end
    if ArcCW.Overflow and self.ActiveElementCache then return self.ActiveElementCache end

    local eles = {}
    local elesLen = 0

    for _, i in ipairs(self.Attachments) do
        if not i.Installed then
            local defaultEles = i.DefaultEles
            if defaultEles then                
                local defaultElesLen = #defaultEles
    
                for i = 1, defaultElesLen do
                    eles[elesLen + i] = defaultEles[i]
                end
                elesLen = elesLen + defaultElesLen
            end
            continue
        end

        local installedEles = i.InstalledEles
        if i.InstalledEles and i.Installed != i.EmptyFallback then
            local installedElesLen = #installedEles

            for i = 1, installedElesLen do
                eles[elesLen + i] = installedEles[i]
            end
            elesLen = elesLen + installedElesLen
        end

        local atttbl = ArcCW.AttachmentTable[i.Installed]

        local activateElements = atttbl.ActivateElements
        if activateElements then
            local activateElementsLen = #activateElements

            for i = 1, activateElementsLen do
                eles[elesLen + i] = activateElements[i]
            end
            elesLen = elesLen + activateElementsLen
        end

        local num = i.ToggleNum or 1
        local toggleStats = atttbl.ToggleStats

        if toggleStats then
            local toggleStatsNum = atttbl.ToggleStats[num]

            if toggleStatsNum and toggleStatsNum.ActivateElements ~= nil then
                local statsActivateElements = toggleStatsNum.ActivateElements
                local statsActivateElementsLen = #statsActivateElements
    
                for i = 1, statsActivateElementsLen do
                    eles[elesLen + i] = statsActivateElements[i]
                end
                elesLen = elesLen + statsActivateElementsLen
            end
        end

        local slots = atttbl.Slot

        if isstring(slots) then
            elesLen = elesLen + 1
            eles[elesLen] = slots
        end

        elesLen = elesLen + 1
        eles[elesLen] = i.Installed
    end

    local defaultElements = self.DefaultElements
    local defaultElementsLen = #defaultElements

    for i = 1, defaultElementsLen do
        eles[elesLen + i] = defaultElements[i]
    end
    elesLen = elesLen + defaultElementsLen

    local mode = self:GetCurrentFiremode()
    if mode and mode.ActivateElements then
        local activateElements = mode.ActivateElements
        local activateElementsLen = #activateElements

        for i = 1, activateElementsLen do
            eles[elesLen + i] = activateElements[i]
        end
        elesLen = elesLen + activateElementsLen
    end

    local eles2 = {}
    local eles2Len = 0

    ArcCW.Overflow = true

    local attachmentElements = self.AttachmentElements
    for f = 1, elesLen do
        local elesElement = eles[f]
        local e = attachmentElements[elesElement]

        if not e then continue end
        if not self:CheckFlags(e.ExcludeFlags, e.RequireFlags) then continue end

        local a = false
        local c = 0

        for g = f, elesLen do
            if eles[g] == elesElement then c = c + 1 end
            if a then continue end

            if c > 1 then a = true end
        end

        if a then continue end

        eles2Len = eles2Len + 1
        eles2[eles2Len] = elesElement
    end

    local flags = self:GetWeaponFlags()
    local flagsLen = #flags
    for i = 1, flagsLen do
        eles2[eles2Len + i] = flags[i]
    end
    eles2Len = eles2Len + flagsLen

    ArcCW.Overflow = false
    self.ActiveElementCache = eles2
    return eles2
end

function SWEP:GetMuzzleDevice(wm)
    local model = self.WM
    local muzz = self.WMModel or self

    if !wm then
        model = self.VM
        muzz = self:GetOwner():GetViewModel()
    end

    if model then
        for _, ele in pairs(model) do
            if ele.IsMuzzleDevice then
                muzz = ele.Model or muzz
            end
        end
    end

    if self:GetInUBGL() then
        local _, slot = self:GetBuff_Override("UBGL")

        if wm then
            muzz = (self.Attachments[slot].WMuzzleDeviceElement or {}).Model or muzz
        else
            muzz = (self.Attachments[slot].VMuzzleDeviceElement or {}).Model or muzz
        end
    end

    return muzz
end

function SWEP:GetTracerOrigin()
    local ow = self:GetOwner()
    local wm = !ow:GetViewModel():IsValid() or ow:ShouldDrawLocalPlayer()
    local muzz = self:GetMuzzleDevice(wm)

    if muzz and muzz:IsValid() then
        local posang = muzz:GetAttachment(self:GetBuff_Override("Override_MuzzleEffectAttachment", self.MuzzleEffectAttachment) or 1)
        if !posang then return muzz:GetPos() end
        local pos = posang.Pos

        return pos
    end
end

function SWEP:CheckFlags(reject, need)
    local flags
    if ArcCW.Overflow then
        flags = self:GetWeaponFlags()
    else
        flags = self:GetActiveElements()
    end

    reject = reject or {}
    need = need or {}

    for _, i in pairs(reject) do
        if table.HasValue(flags, i) then
            return false
        end
    end

    for _, i in pairs(need) do
        if !table.HasValue(flags, i) then
            return false
        end
    end

    return true
end

function SWEP:GetWeaponFlags()
    local flags = {}

    if self.DefaultFlags then table.Add(flags, self.DefaultFlags) end

    for id, i in pairs(self.Attachments) do
        if !i.Installed then
            if i.DefaultFlags then
                table.Add(flags, i.DefaultFlags)
            end
            continue
        end

        local buff = self:GetBuff_Stat("GivesFlags", id)
        if buff then
            table.Add(flags, buff)
        end

        if i.GivesFlags then
            table.Add(flags, i.GivesFlags)
        end

        local extras = {}
        self:GetBuff_Hook("Hook_ExtraFlags", extras)
        table.Add(flags, extras)

        table.Add(flags, {i.Installed})
    end

    return flags
end

function SWEP:PlayerOwnsAtt(att)
    local qty = ArcCW:PlayerGetAtts(self:GetOwner(), att)

    return qty > 0
end

function SWEP:NetworkWeapon(sendto)
    net.Start("arccw_networkatts")
    net.WriteEntity(self) -- self entity

    net.WriteUInt(table.Count(self.Attachments), 8)

    for _, i in pairs(self.Attachments) do
        if !i.Installed then net.WriteUInt(0, ArcCW.GetBitNecessity()) continue end

        local atttbl = ArcCW.AttachmentTable[i.Installed]
        local id = atttbl.ID

        net.WriteUInt(id, ArcCW.GetBitNecessity())

        if i.SlideAmount then
            net.WriteFloat(i.SlidePos or 0.5)
        end

        if atttbl.ToggleStats then
            net.WriteUInt(i.ToggleNum or 1, 8) -- look if you want more than 255 fucking toggle options you're insane and stupid just don't ok
        end

        -- if atttbl.ColorOptionsTable then
        --     net.WriteUInt(i.ColorOptionIndex or 1, 8) -- look if you want more than 256 fucking color options you're insane and stupid and just don't ok
        -- end
    end

    if sendto then
        net.Send(sendto)
    else
        net.SendPVS(self:GetPos())
        --net.Broadcast()
    end
end

function SWEP:SendDetail_ColorIndex(slot)
    net.Start("arccw_colorindex")
    net.WriteUInt(slot, 8)
    net.WriteUInt(self.Attachments[slot].ColorOptionIndex)
    net.SendToServer()
end

function SWEP:SendDetail_SlidePos(slot, hmm)
    if !self.Attachments then return end
    if !self.Attachments[slot].SlidePos then return end

    net.Start("arccw_slidepos")
    net.WriteUInt(slot, 8)
    net.WriteFloat(self.Attachments[slot].SlidePos or 0.5)
    net.SendToServer()
end

function SWEP:SendDetail_ToggleNum(slot, hmm)
    if !self.Attachments or !self.Attachments[slot] then return end
    if !self.Attachments[slot].ToggleNum then return end

    net.Start("arccw_togglenum")
    net.WriteUInt(slot, 8)
    net.WriteUInt(self.Attachments[slot].ToggleNum or 1, 8)
    net.SendToServer()
end


function SWEP:SendAllDetails()
    for i, k in pairs(self.Attachments) do
        self:SendDetail_SlidePos(i, true)
        self:SendDetail_ToggleNum(i, true)
    end
end

function SWEP:CountAttachments()
    local total = 0

    for _, i in pairs(self.Attachments) do
        if i.Installed and !i.FreeSlot then
            local ins = ArcCW.AttachmentTable[i.Installed]
            if ins and !ins.IgnorePickX then
                total = total + 1
            end
        end
    end

    return total
end

function SWEP:SetBodygroupTr(ind, bg)
    self.Bodygroups[ind] = bg
end

function SWEP:RefreshBGs()
    local vm

    local vmm = self:GetBuff_Override("Override_VMMaterial") or self.VMMaterial or ""
    local wmm = self:GetBuff_Override("Override_WMMaterial") or self.WMMaterial or  ""

    local vmc = self:GetBuff_Override("Override_VMColor") or self.VMColor or Color(255, 255, 255)
    local wmc = self:GetBuff_Override("Override_WMColor") or self.WMColor or Color(255, 255, 255)

    local vms = self:GetBuff_Override("Override_VMSkin") or self.DefaultSkin
    local wms = self:GetBuff_Override("Override_WMSkin") or self.DefaultWMSkin

    local vmp = self.DefaultPoseParams
    local wmp = self.DefaultWMPoseParams

    if self.MirrorVMWM then
        wmm = vmm
        wmc = vmc
        wms = vms
        wmp = vmp
    end

    if self:GetOwner():IsPlayer() then
        vm = self:GetOwner():GetViewModel()
    end

    if vm and vm:IsValid() then
        ArcCW.SetBodyGroups(vm, self.DefaultBodygroups)
        vm:SetMaterial(vmm)
        vm:SetColor(vmc)
        vm:SetSkin(vms)

        vmp["BaseClass"] = nil

        for i, k in pairs(vmp) do
            vm:SetPoseParameter(i, k)
        end
    end

    self:SetMaterial(wmm)
    self:SetColor(wmc)
    self:SetSkin(wms)

    if self.WMModel and self.WMModel:IsValid() then
        ArcCW.SetBodyGroups(self.WMModel, self.MirrorVMWM and self.DefaultBodygroups or self.DefaultWMBodygroups)

        self.WMModel:SetMaterial(wmm)
        self.WMModel:SetColor(wmc)
        self.WMModel:SetSkin(wms)

        wmp["BaseClass"] = nil

        for i, k in pairs(wmp) do
            self.WMModel:SetPoseParameter(i, k)
        end
    end

    local ae = self:GetActiveElements()

    for _, e in pairs(ae) do
        local ele = self.AttachmentElements[e]

        if !ele then continue end

        if ele.VMPoseParams and vm and IsValid(vm) then
            ele.VMPoseParams["BaseClass"] = nil
            for i, k in pairs(ele.VMPoseParams) do
                vm:SetPoseParameter(i, k)
            end
        end

        if self.WMModel and self.WMModel:IsValid() then
            if self.MirrorVMWM and ele.VMPoseParams then
                ele.VMPoseParams["BaseClass"] = nil
                for i, k in pairs(ele.VMPoseParams) do
                    self.WMModel:SetPoseParameter(i, k)
                end
            end
            if ele.WMPoseParams then
                ele.WMPoseParams["BaseClass"] = nil
                for i, k in pairs(ele.WMPoseParams) do
                    self.WMModel:SetPoseParameter(i, k)
                end
            end
        end

        if ele.VMSkin and vm and IsValid(vm) then
            vm:SetSkin(ele.VMSkin)
        end

        if self.WMModel and self.WMModel:IsValid() then
            if self.MirrorVMWM and ele.VMSkin then
                self.WMModel:SetSkin(ele.VMSkin)
                self:SetSkin(ele.VMSkin)
            end
            if ele.WMSkin then
                self.WMModel:SetSkin(ele.WMSkin)
                self:SetSkin(ele.WMSkin)
            end
        end

        if ele.VMColor and vm and IsValid(vm) then
            vm:SetColor(ele.VMColor)
        end

        if self.WMModel and self.WMModel:IsValid() then
            if self.MirrorVMWM and ele.VMSkin then
                self.WMModel:SetColor(ele.VMColor or color_white)
                self:SetColor(ele.VMColor or color_white)
            end
            if ele.WMSkin then
                self.WMModel:SetColor(ele.WMColor or color_white)
                self:SetColor(ele.WMColor or color_white)
            end
        end

        if ele.VMMaterial and vm and IsValid(vm) then
            vm:SetMaterial(ele.VMMaterial)
        end

        if self.WMModel and self.WMModel:IsValid() then
            if self.MirrorVMWM and ele.VMMaterial then
                self.WMModel:SetMaterial(ele.VMMaterial)
                self:SetMaterial(ele.VMMaterial)
            end
            if ele.WMMaterial then
                self.WMModel:SetMaterial(ele.WMMaterial)
                self:SetMaterial(ele.WMMaterial)
            end
        end

        if ele.VMBodygroups then
            for _, i in pairs(ele.VMBodygroups) do
                if !i.ind or !i.bg then continue end

                if vm and IsValid(vm) and vm:GetBodygroup(i.ind) != i.bg then
                    vm:SetBodygroup(i.ind, i.bg)
                end
            end

            if self.MirrorVMWM then
                for _, i in pairs(ele.VMBodygroups) do
                    if !i.ind or !i.bg then continue end

                    if self.WMModel and IsValid(self.WMModel) and self.WMModel:GetBodygroup(i.ind) != i.bg then
                        self.WMModel:SetBodygroup(i.ind, i.bg)
                    end

                    if self:GetBodygroup(i.ind) != i.bg then
                        self:SetBodygroup(i.ind, i.bg)
                    end
                end
            end
        end

        if ele.WMBodygroups then
            for _, i in pairs(ele.WMBodygroups) do
                if !i.ind or !i.bg then continue end

                if self.WMModel and IsValid(self.WMModel) and self.WMModel:GetBodygroup(i.ind) != i.bg then
                    self.WMModel:SetBodygroup(i.ind, i.bg)
                end

                if self:GetBodygroup(i.ind) != i.bg then
                    self:SetBodygroup(i.ind, i.bg)
                end
            end
        end

        if ele.VMBoneMods then
            for bone, i in pairs(ele.VMBoneMods) do
                local boneind = vm:LookupBone(bone)

                if !boneind then continue end

                vm:ManipulateBonePosition(boneind, i)
            end

            if self.MirrorVMWM then
                for bone, i in pairs(ele.VMBoneMods) do
                    if !(self.WMModel and self.WMModel:IsValid()) then break end
                    local boneind = self:LookupBone(bone)

                    if !boneind then continue end

                    self:ManipulateBonePosition(boneind, i)
                end
            end
        end

        if ele.WMBoneMods then
            for bone, i in pairs(ele.WMBoneMods) do
                if !(self.WMModel and self.WMModel:IsValid()) then break end
                local boneind = self:LookupBone(bone)

                if !boneind then continue end

                self:ManipulateBonePosition(boneind, i)
            end
        end



        if SERVER then
            self:SetupShields()
        end
    end

    if IsValid(vm) then
        for i = 0, (vm:GetNumBodyGroups()) do
            if self.Bodygroups[i] then
                vm:SetBodygroup(i, self.Bodygroups[i])
            end
        end

        self:GetBuff_Hook("Hook_ModifyBodygroups", {vm = vm, eles = ae, wm = false})
        self:GetBuff_Hook("Hook_ModifyBodygroups", {vm = self.WMModel or self, eles = ae, wm = true})

        for slot, v in pairs(self.Attachments) do
            if !v.Installed then continue end

            local func = self:GetBuff_Stat("Hook_ModifyAttBodygroups", slot)
            if func and v.VElement and IsValid(v.VElement.Model) then
                func(self, {vm = vm, element = v.VElement, slottbl = v, wm = false})
            end
            if func and v.WElement and IsValid(v.WElement.Model)  then
                func(self, {vm = self.WMModel, element = v.WElement, slottbl = v, wm = true})
            end
        end
    end
end

function SWEP:GetPickX()
    return GetConVar("arccw_atts_pickx"):GetInt()
end

function SWEP:Attach(slot, attname, silent, noadjust)
    silent = silent or false
    local attslot = self.Attachments[slot]
    if !attslot then return end
    if attslot.Installed == attname then return end
    if attslot.Internal then return end

    -- Make an additional check to see if we can detach the current attachment
    if attslot.Installed and !ArcCW:PlayerCanAttach(self:GetOwner(), self, attslot.Installed, slot, attname) then
        if CLIENT and !silent then
            surface.PlaySound("items/medshotno1.wav")
        end
        return
    end

    if !ArcCW:PlayerCanAttach(self:GetOwner(), self, attname, slot, false) then
        if CLIENT and !silent then
            surface.PlaySound("items/medshotno1.wav")
        end
        return
    end

    local pick = self:GetPickX()

    if pick > 0 and self:CountAttachments() >= pick and !attslot.FreeSlot
            and !attslot.Installed then
        if CLIENT and !silent then
            surface.PlaySound("items/medshotno1.wav")
        end
        return
    end

    local atttbl = ArcCW.AttachmentTable[attname]

    if !atttbl then return end
    if !ArcCW:SlotAcceptsAtt(attslot.Slot, self, attname) then return end
    if !self:CheckFlags(atttbl.ExcludeFlags, atttbl.RequireFlags) then return end
    if !self:PlayerOwnsAtt(attname) then return end

    local max = atttbl.Max

    if max then
        local amt = 0

        for i, k in pairs(self.Attachments) do
            if k.Installed == attname then amt = amt + 1 end
        end

        if amt >= max then return end
    end

    if attslot.SlideAmount then
        attslot.SlidePos = 0.5
    end

    if atttbl.MountPositionOverride then
        attslot.SlidePos = atttbl.MountPositionOverride
    end

    if atttbl.AdditionalSights then
        self.SightMagnifications = {}
    end

    if atttbl.ToggleStats then
        attslot.ToggleNum = 1
    end

    attslot.ToggleLock = atttbl.ToggleLockDefault or false

    if CLIENT then
        -- we are asking to attach something

        self:SendAllDetails()

        net.Start("arccw_asktoattach")
        net.WriteUInt(slot, 8)
        net.WriteUInt(atttbl.ID, 24)
        net.SendToServer()

		local sndi
		if custsounds:GetBool() then
			if oldmenu:GetBool() then
				sndi = "weapons/cw/attach.wav"
			else
				sndi = "weapons/arccw/install.wav"
			end
		else
			silent = true
		end
        if !silent then
            surface.PlaySound(atttbl.AttachSound or sndi)
        end
    else
        self:DetachAllMergeSlots(slot)

        for i, k in pairs(self.Attachments) do
            if table.HasValue(k.MergeSlots or {}, slot) then
                self:DetachAllMergeSlots(i)
            end
        end
    end

    attslot.Installed = attname

    if atttbl.Health then
        attslot.HP = self:GetAttachmentMaxHP(slot)
    end

    if atttbl.ColorOptionsTable then
        attslot.ColorOptionIndex = 1
    end

    ArcCW:PlayerTakeAtt(self:GetOwner(), attname)

    --[[]
    local fmt = self:GetBuff_Override("Override_Firemodes") or self.Firemodes
    local fmi = self:GetFireMode()

    if fmi > table.Count(fmt) then
        self:SetFireMode(1)
    end
    ]]

    --self.UnReady = false

    if SERVER then
        self:NetworkWeapon()
        self:SetupModel(false)
        self:SetupModel(true)
        ArcCW:PlayerSendAttInv(self:GetOwner())

        if engine.ActiveGamemode() == "terrortown" then
            self:TTT_PostAttachments()
        end
    else
        self:SetupActiveSights()

        self.LHIKAnimation = 0
        self.LHIKAnimationStart = 0
        self.LHIKAnimationTime = 0

        self.LHIKDelta = {}
        self.LHIKDeltaAng = {}

        self.ViewModel_Hit = Vector(0, 0, 0)

        if !silent then
            self:SavePreset("autosave")
        end
    end

    for s, i in pairs(self.Attachments) do
        if !self:CheckFlags(i.ExcludeFlags, i.RequireFlags) then
            self:Detach(s, true, true)
        end
    end

    if !noadjust then
        self:AdjustAtts()
    end

    if atttbl.UBGL then
        local ubgl_ammo = self:GetBuff_Override("UBGL_Ammo")
        local ubgl_clip = self:GetBuff_Override("UBGL_Capacity")
        if self:GetOwner():IsPlayer() and GetConVar("arccw_atts_ubglautoload"):GetBool() and ubgl_ammo then
            local amt = math.min(ubgl_clip - self:Clip2(), self:GetOwner():GetAmmoCount(ubgl_ammo))
            self:SetClip2(self:Clip2() + amt)
            self:GetOwner():RemoveAmmo(amt, ubgl_ammo)
        end
    end

    self:RefreshBGs()
    return true
end

function SWEP:DetachAllMergeSlots(slot, silent)
    local slots = {slot}

    table.Add(slots, (self.Attachments[slot] or {}).MergeSlots or {})

    for _, i in pairs(slots) do
        self:Detach(i, silent, nil, true)
    end
end

function SWEP:Detach(slot, silent, noadjust, nocheck)
    if !slot then return end
    if !self.Attachments[slot] then return end

    if !self.Attachments[slot].Installed then return end

    if self.Attachments[slot].Internal then return end

    if !nocheck and !ArcCW:PlayerCanAttach(self:GetOwner(), self, self.Attachments[slot].Installed, slot, true) then
        if CLIENT and !silent then
            surface.PlaySound("items/medshotno1.wav")
        end
        return
    end

    if self.Attachments[slot].Installed == self.Attachments[slot].EmptyFallback then
        return
    end

    local previnstall = self.Attachments[slot].Installed

    local atttbl = ArcCW.AttachmentTable[previnstall]

    if atttbl.UBGL then
        local clip = self:Clip2()

        local ammo = atttbl.UBGL_Ammo or "smg1_grenade"

        if SERVER and IsValid(self:GetOwner()) then
            self:GetOwner():GiveAmmo(clip, ammo, true)
        end

        self:SetClip2(0)

        self:DeselectUBGL()
    end

    if self.Attachments[slot].EmptyFallback then -- is this a good name
        self.Attachments[slot].Installed = self.Attachments[slot].EmptyFallback
    else
        self.Attachments[slot].Installed = nil
    end

    if self.Attachments[slot].SubAtts then
        for i, k in pairs(self.Attachments[slot].SubAtts) do
            self:Detach(k, true, true)
        end
    end

    if self:GetAttachmentHP(slot) >= self:GetAttachmentMaxHP(slot) then
        ArcCW:PlayerGiveAtt(self:GetOwner(), previnstall)
    end

    if CLIENT then
        self:SendAllDetails()

        -- we are asking to detach something
        net.Start("arccw_asktodetach")
        net.WriteUInt(slot, 8)
        net.SendToServer()

		local sndi
		if custsounds:GetBool() then
			if oldmenu:GetBool() then
				sndi = "weapons/cw/detach.wav"
			else
				sndi = "weapons/arccw/uninstall.wav"
			end
		else
			silent = true
		end
        if !silent then
            surface.PlaySound(atttbl.DetachSound or sndi)
        end

        self:SetupActiveSights()

        self.LHIKAnimation = 0
        self.LHIKAnimationStart = 0
        self.LHIKAnimationTime = 0

        if !silent then
            self:SavePreset("autosave")
        end
    else
        self:NetworkWeapon()
        self:SetupModel(false)
        self:SetupModel(true)
        ArcCW:PlayerSendAttInv(self:GetOwner())

        if engine.ActiveGamemode() == "terrortown" then
            self:TTT_PostAttachments()
        end
    end

    self:RefreshBGs()

    if !noadjust then
        self:AdjustAtts()
    end
    return true
end

function SWEP:ToggleSlot(slot, num, silent, back)
    local atttbl = ArcCW.AttachmentTable[self.Attachments[slot].Installed]
    if !atttbl.ToggleStats then return end

    local amt = 1

    if back then amt = -1 end

    if !num then
        self.Attachments[slot].ToggleNum = (self.Attachments[slot].ToggleNum or 1) + amt
        if self.Attachments[slot].ToggleNum > #atttbl.ToggleStats then
            self.Attachments[slot].ToggleNum = 1
        elseif self.Attachments[slot].ToggleNum < 1 then
            self.Attachments[slot].ToggleNum = #atttbl.ToggleStats
        end
    else
        self.Attachments[slot].ToggleNum = math.Clamp(num, 1, #catttbl.ToggleStats)
    end

    if CLIENT then
        self:SendDetail_ToggleNum(slot)
        self:SetupActiveSights()
    elseif SERVER then
        self:NetworkWeapon()
        self:SetupModel(false)
        self:SetupModel(true)
    end

    self:AdjustAtts()

    for s, i in pairs(self.Attachments) do
        if !self:CheckFlags(i.ExcludeFlags, i.RequireFlags) then
            self:Detach(s, true)
        end
    end

    self:RefreshBGs()

    if CLIENT and !silent and self:GetBuff_Stat("ToggleSound", slot) != false then
        surface.PlaySound(self:GetBuff_Stat("ToggleSound", slot) or (atttbl.ToggleStats[slot] or {}).ToggleSound or "weapons/arccw/firemode.wav")
    end
end

function SWEP:AdjustAmmo(old_inf)

    local new_inf = self:HasInfiniteAmmo()

    local wpn = weapons.Get(self:GetClass())
    local ammo = self:GetBuff_Override("Override_Ammo", wpn.Primary.Ammo)
    local oldammo = self.OldAmmo or self.Primary.Ammo

    if old_inf and (!new_inf or ammo != oldammo) then
        self:SetClip1(0)
    elseif (!old_inf and new_inf) or ammo != oldammo then
        self:Unload()
    end

    self.Primary.Ammo = ammo
    self.OldAmmo = self.Primary.Ammo
end

function SWEP:AdjustAtts()
    local old_inf = self:HasInfiniteAmmo()

    self:RecalcAllBuffs()

    -- Recalculate active elements so dependencies aren't fucked
    self.ActiveElementCache = nil
    self:GetActiveElements(true)
    self.ModifiedCache = {}

    -- Tempoarily disable modified cache, since we're building it right now
    MODIFIED_CACHE = false

    for i, k in pairs(self.Attachments) do
        if !k.Installed then continue end
        local ok = true

        if !ArcCW:SlotAcceptsAtt(k.Slot, self, k.Installed) then ok = false end
        if ok and !self:CheckFlags(k.ExcludeFlags, k.RequireFlags) then ok = false end

        local atttbl = ArcCW.AttachmentTable[k.Installed]

        if !atttbl then continue end
        if ok and !self:CheckFlags(atttbl.ExcludeFlags, atttbl.RequireFlags) then ok = false end

        if !ok then
            self:Detach(i, true)
            continue
        end

        -- Cache all possible value modifiers
        for var, v in pairs(atttbl) do
            self.ModifiedCache[var] = true
            if var == "ToggleStats" or var == "Override_Firemodes" then
                for _, v2 in pairs(v) do
                    for var2, _ in pairs(v2) do
                        self.ModifiedCache[var2] = true
                    end
                end
            end
        end
    end

    for _, e in pairs(self.AttachmentElements) do
        if !istable(e) then continue end
        for var, v in pairs(e) do
            self.ModifiedCache[var] = true
        end
    end

    for _, e in pairs(self.Firemodes) do
        if !istable(e) then continue end
        for var, v in pairs(e) do
            self.ModifiedCache[var] = true
        end
    end

    MODIFIED_CACHE = true

    if SERVER then
        local cs = self:GetCapacity() + self:GetChamberSize()

        if self:Clip1() > cs and self:Clip1() != ArcCW.BottomlessMagicNumber then
            local diff = self:Clip1() - cs
            self:SetClip1(cs)

            if self:GetOwner():IsValid() and !self:GetOwner():IsNPC() then
                self:GetOwner():GiveAmmo(diff, self.Primary.Ammo, true)
            end
        end
    else
        local se = self:GetBuff_Override("Override_ShootEntity") or self.ShootEntity
        if se then
            local path = "arccw/weaponicons/" .. self:GetClass()
            local mat = Material(path)

            if !mat:IsError() then
                local tex = mat:GetTexture("$basetexture")
                local texpath = tex:GetName()

                killicon.Add(se, texpath, Color(255, 255, 255))
            end
        end
    end

    local ubgl_ammo = self:GetBuff_Override("UBGL_Ammo")
    local ubgl_clip = self:GetBuff_Override("UBGL_Capacity")

    self.Secondary.ClipSize = ubgl_clip or -1
    self.Secondary.Ammo = ubgl_ammo or "none"

    --[[]
    if ubgl_clip then
        self.Secondary.ClipSize = ubgl_clip
        if self:GetOwner():IsPlayer() and GetConVar("arccw_atts_ubglautoload"):GetBool() and ubgl_ammo then
            local amt = math.min(ubgl_clip - self:Clip2(), self:GetOwner():GetAmmoCount(ubgl_ammo))
            self:SetClip2(self:Clip2() + amt)
            self:GetOwner():RemoveAmmo(amt, ubgl_ammo)
        end
    else
        self.Secondary.ClipSize = -1
    end
    ]]



    self:RebuildSubSlots()

    local fmt = self:GetBuff_Override("Override_Firemodes", self.Firemodes)
    fmt["BaseClass"] = nil

    local fmi = self:GetFireMode()
    if !fmt[fmi] then self:SetFireMode(1) end

    self:AdjustAmmo(old_inf)
end


function SWEP:GetAttachmentMaxHP(slot)
    if !self.Attachments[slot] then return 100 end
    if !self.Attachments[slot].Installed then return 100 end
    local maxhp = 100
    local atttbl = ArcCW.AttachmentTable[self.Attachments[slot].Installed]

    if atttbl.Health then
        maxhp = atttbl.Health
    end

    return maxhp
end

function SWEP:GetAttachmentHP(slot)
    if !self.Attachments[slot] then return 100 end
    if !self.Attachments[slot].Installed then return 100 end

    if self.Attachments[slot].HP then return self.Attachments[slot].HP end

    self.Attachments[slot].HP = self:GetAttachmentMaxHP(slot)

    return self.Attachments[slot].HP
end

function SWEP:ApplyAttachmentShootDamage()
    local any = false
    for j, i in pairs(self.Attachments) do
        if !i.Installed then continue end
        local atttbl = ArcCW.AttachmentTable[i.Installed]

        if !atttbl.Health then continue end

        if atttbl.DamageOnShoot then
            self:DamageAttachment(j, atttbl.DamageOnShoot)
            any = true
        end
    end

    if any then
        self:SendAttHP()
    end
end

function SWEP:DamageAttachment(slot, dmg)
    if !self.Attachments[slot] then return end
    if !self.Attachments[slot].Installed then return end

    self.Attachments[slot].HP = self:GetAttachmentHP(slot) - dmg

    if self:GetAttachmentHP(slot) <= 0 then
        local atttbl = ArcCW.AttachmentTable[self.Attachments[slot].Installed]

        if atttbl.Hook_AttDestroyed then
            atttbl.Hook_AttDestroyed(self, {slot = slot, dmg = dmg})
        end

        self:Detach(slot, true)
    end
end

function SWEP:SendAttHP()
	if CLIENT then return end -- Uhhhhh
    net.Start("arccw_sendatthp")
    for i, k in pairs(self.Attachments) do
        if !k.Installed then continue end
        local atttbl = ArcCW.AttachmentTable[k.Installed]

        if atttbl.Health then
            net.WriteBool(true)
            net.WriteUInt(i, 8)
            net.WriteFloat(self:GetAttachmentHP(i))
        end
    end
    net.WriteBool(false)
    net.Send(self:GetOwner())
end

-- local node = {b = {}, i = "" t = 0}
-- b: branches
-- i: installed
-- t: toggle
-- s: slide
-- h: hp

-- recursive function
-- gets a tree of all the attachments installed in subslots subordinate to a particular slot
function SWEP:GetSubSlotTree(i)
    if !self.Attachments[i] then return nil end
    if !self.Attachments[i].Installed then return nil end
    if !self.Attachments[i].SubAtts then return
        {
        b = {},
        i = self.Attachments[i].Installed,
        t = self.Attachments[i].ToggleNum,
        s = self.Attachments[i].SlidePos,
        h = self.Attachments[i].Health}
    end

    local ss = {}
    for j, k in pairs(self.Attachments[i].SubAtts) do
        if k == i then continue end
        local sst = self:GetSubSlotTree(k)
        if sst then
            ss[j] = sst
        end
    end

    return {b = ss, i = self.Attachments[i].Installed}
end

function SWEP:SubSlotTreeReinstall(slot, subslottree)
    for i, k in pairs(self.Attachments[slot].SubAtts or {}) do
        -- i = index
        -- k = slot
        self.Attachments[k].Installed = subslottree[i].i
        self.Attachments[k].ToggleNum = subslottree[i].t
        self.Attachments[k].SlidePos = subslottree[i].s
        self.Attachments[k].Health = subslottree[i].h

        if subslottree.b[i] then
            self:SubSlotTreeReinstall(i, subslottree.b[i])
        end
    end
end

function SWEP:RebuildSubSlots()
    -- this function rebuilds the subslots while preserving installed attachment data
    local subslottrees = {}

    local baseatts = table.Count(weapons.Get(self:GetClass()).Attachments)

    self.Attachments.BaseClass = nil

    for i = 1, baseatts do
        subslottrees[baseatts] = self:GetSubSlotTree(i)
    end

    -- remove all sub slots
    for i, k in pairs(self.Attachments) do
        if !isnumber(i) then continue end
        if !istable(k) then continue end
        if i > baseatts then
            self.Attachments[i] = nil
        else
            self.Attachments[i].SubAtts = nil
        end
    end

    self.SubSlotCount = 0
    -- add the sub slots back
    for i, k in pairs(self.Attachments) do
        if !k.Installed then continue end
        local att = ArcCW.AttachmentTable[k.Installed]
        if !att then continue end
        if !istable(k) then continue end

        if att.SubSlots then
            self:AddSubSlot(i, k.Installed)
        end
    end
    -- add the sub slot data back

    for i, k in pairs(subslottrees) do
        self:SubSlotTreeReinstall(i, k)
    end
end

function SWEP:AddSubSlot(i, attname)
    local baseatts = table.Count(weapons.Get(self:GetClass()).Attachments)
    local att = ArcCW.AttachmentTable[attname]
    if att.SubSlots then
        self.Attachments[i].SubAtts = {}
        local og_slot = self.Attachments[i]
        for ind, slot in pairs(att.SubSlots) do
            if !istable(slot) then continue end
            self.SubSlotCount = self.SubSlotCount + 1
            local index = baseatts + self.SubSlotCount
            self.Attachments[index] = slot
            self.Attachments[index].Bone = og_slot.Bone
            self.Attachments[index].WMBone = og_slot.WMBone
            self.Attachments[index].ExtraSightDist = 0--self.Attachments[index].ExtraSightDist or og_slot.ExtraSightDist
            self.Attachments[index].CorrectivePos = og_slot.CorrectivePos
            self.Attachments[index].CorrectiveAng = og_slot.CorrectiveAng
            og_slot.SubAtts[ind] = index

            if slot.MergeSlots then
                self.Attachments[index].MergeSlots = {}
                for _, k2 in pairs(slot.MergeSlots) do
                    table.insert(self.Attachments[index].MergeSlots, k2 + index)
                end
            end

            if slot.Offset then
                self.Attachments[index].Offset = {
                    vpos = Vector(0, 0, 0),
                    vang = Angle(0, 0, 0),
                    wpos = Vector(0, 0, 0),
                    wang = Angle(0, 0, 0)
                }

                if slot.Offset.vang then
                    self.Attachments[index].Offset.vang = slot.Offset.vang + (og_slot.Offset.vang or Angle(0, 0, 0))
                end

                if slot.Offset.wang then
                    self.Attachments[index].Offset.wang = slot.Offset.wang + (og_slot.Offset.wang or Angle(0, 0, 0))
                end

                if slot.Offset.vpos then
                    self.Attachments[index].Offset.vpos = LocalToWorld(slot.Offset.vpos, self.Attachments[index].Offset.vang, og_slot.Offset.vpos, og_slot.Offset.vang or Angle(0, 0, 0))
                end

                if slot.Offset.wpos then
                    self.Attachments[index].Offset.wpos = LocalToWorld(slot.Offset.wpos, self.Attachments[index].Offset.wang, og_slot.Offset.wpos, og_slot.Offset.wang or Angle(0, 0, 0))
                end
            end

            self.Attachments[index].SubAtts = {}
        end
    end
end