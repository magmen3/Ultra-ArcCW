EFFECT.StartPos = Vector(0, 0, 0)
EFFECT.EndPos = Vector(0, 0, 0)
EFFECT.StartTime = 0
EFFECT.LifeTime = 0.2
EFFECT.LifeTime2 = 0.2
EFFECT.DieTime = 0
EFFECT.Color = Color(255, 255, 255)
EFFECT.Speed = 5000

-- local head = Material("effects/whiteflare")
local tracer = Material("effects/smoke_trail")
local smoke = Material("trails/smoke")

function EFFECT:Init(data)

    local hit = data:GetOrigin()
    local wep = data:GetEntity()

    if !IsValid(wep) then return end

    local speed = data:GetScale()
    local start = (wep.GetTracerOrigin and wep:GetTracerOrigin()) or data:GetStart()

    if GetConVar("arccw_fasttracers"):GetBool() then
            local fx = EffectData()
            fx:SetOrigin(hit)
            fx:SetEntity(wep)
            fx:SetStart(start)
            fx:SetScale(4000)
            util.Effect("tracer", fx)
            self:Remove()
        return
    end

    if speed > 0 then
        self.Speed = speed
    end

    local profile = 0
    if wep.GetBuff_Override then
        profile = wep:GetBuff_Override("Override_PhysTracerProfile", wep.PhysTracerProfile) or 0
        if isnumber(profile) then profile = ArcCW.BulletProfileDict[ArcCW.BulletProfiles[profile]] end
    end

    self.LifeTime = (hit - start):Length() / self.Speed

    self.StartTime = UnPredictedCurTime()
    self.DieTime = UnPredictedCurTime() + math.max(self.LifeTime, self.LifeTime2)

    self.StartPos = start
    self.EndPos = hit
    self.Color = (ArcCW.BulletProfileDict[profile] or ArcCW.BulletProfileDict["default0"]).color
end

function EFFECT:Think()
    return self.DieTime > UnPredictedCurTime()
end

local function LerpColor(d, col1, col2)
    local r = Lerp(d, col1.r, col2.r)
    local g = Lerp(d, col1.g, col2.g)
    local b = Lerp(d, col1.b, col2.b)
    local a = Lerp(d, col1.a, col2.a)
    return Color(r, g, b, a)
end

local smoker, smoked = Color(155, 155, 155, 155), Color(155, 155, 155, 0)
function EFFECT:Render()
    local d = (UnPredictedCurTime() - self.StartTime) / self.LifeTime
    local d2 = (UnPredictedCurTime() - self.StartTime) / self.LifeTime2
    local startpos = self.StartPos + (d * 0.1 * (self.EndPos - self.StartPos))
    local endpos = self.StartPos + (d * (self.EndPos - self.StartPos))
    local size = 1

    local col = self.Color --LerpColor(d, self.Color, Color(0, 0, 0, 0))
    local col2 = LerpColor(d2, smoker, smoked)

    -- render.SetMaterial(head)
    -- render.DrawSprite(endpos, size * 3, size * 3, col)

    render.SetMaterial(tracer)
    render.DrawBeam(endpos, startpos, size, 0, 1, col)

    render.SetMaterial(smoke)
    render.DrawBeam(self.EndPos, self.StartPos, size * 0.5 * d2, 0, 1, col2)
end
