-- spawn-castle-fixed.lua (LocalScript)
-- Лёгкий стабильный спавн модели (замок) по фиксированным координатам/углам.
-- Настройки вверху — правь только их.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- ====== Настройки (редактируй) ======
local ASSET_ID       = "rbxassetid://128743514073638"   -- id замка
local SPAWN_POS      = Vector3.new(-28.000, 15.000, -4.000)
local SPAWN_ROT_DEG  = Vector3.new(0, -90.000, 0)       -- (pitch, yaw, roll) в градусах
local ANCHOR_PARTS   = true                             -- анкерить все BasePart в модели
local ENABLE_MONITOR = false                            -- если true — будет печатать координаты модели
local MONITOR_INTERVAL = 0.25                           -- сек (только если ENABLE_MONITOR=true)
-- ====================================

local function fmt(n) return string.format("%.3f", tonumber(n) or 0) end

local function findAnyBasePart(m)
    if not m then return nil end
    if m.PrimaryPart and m.PrimaryPart:IsA("BasePart") then return m.PrimaryPart end
    return m:FindFirstChildWhichIsA("BasePart", true)
end

local function cframeFromPosRot(pos, rotDeg)
    local rot = CFrame.Angles(math.rad(rotDeg.X), math.rad(rotDeg.Y), math.rad(rotDeg.Z))
    return CFrame.new(pos) * rot
end

local function uniqueName(base)
    if not base or base == "" then base = "Model" end
    local name = base
    local i = 1
    while Workspace:FindFirstChild(name) do
        i = i + 1
        name = base .. tostring(i)
    end
    return name
end

local function spawnModel(assetId)
    if not assetId or assetId == "" then
        warn("spawn-castle: пустой assetId")
        return nil
    end
    local ok, objs = pcall(function() return game:GetObjects(assetId) end)
    if not ok or not objs or #objs == 0 then
        warn("spawn-castle: не удалось загрузить asset:", assetId)
        return nil
    end
    local model = objs[1]
    if not model then return nil end
    -- не менять исходный объект — клонируем
    local clone = model:Clone()
    clone.Name = uniqueName(model.Name or "Model")
    return clone
end

local function placeModel(model, targetCFrame, anchorParts)
    if not model then return false end
    -- ставим в Workspace чтобы методы работали
    model.Parent = Workspace

    -- если есть PrimaryPart/любая базовая часть, используем PivotTo (без необходимости присваивать PrimaryPart)
    local ok, err = pcall(function()
        if model:IsA("Model") then
            if model.PrimaryPart then
                model:SetPrimaryPartCFrame(targetCFrame)
            else
                -- PivotTo работает для моделей: ставим через :PivotTo
                if model.PivotTo then
                    model:PivotTo(targetCFrame)
                else
                    -- fallback: попытка установить CFrame для первой BasePart
                    local part = findAnyBasePart(model)
                    if part then
                        part.CFrame = targetCFrame
                    end
                end
            end
        end
    end)
    if not ok then
        warn("spawn-castle: placement warning:", err)
    end

    if anchorParts then
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("BasePart") then
                pcall(function()
                    d.Anchored = true
                    d.AssemblyLinearVelocity  = Vector3.new(0,0,0)
                    d.AssemblyAngularVelocity = Vector3.new(0,0,0)
                end)
            end
        end
    end
    return true
end

local function startMonitor(model)
    if not model or not ENABLE_MONITOR then return end
    local lastCf = nil
    local acc = 0
    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        acc = acc + dt
        if acc < MONITOR_INTERVAL then return end
        acc = 0
        local ok, cf = pcall(function()
            if model.PrimaryPart then return model:GetPrimaryPartCFrame() end
            if model:GetBoundingBox then local bcf, _ = model:GetBoundingBox() return bcf end
            return nil
        end)
        if not ok or not cf then
            if conn then conn:Disconnect() end
            print("spawn-castle: монитор остановлен (модель могла быть удалена)")
            return
        end
        if not lastCf or (cf.Position - lastCf.Position).Magnitude > 0.01 then
            local px,py,pz = cf.Position.X, cf.Position.Y, cf.Position.Z
            local rx,ry,rz = cf:ToEulerAnglesXYZ()
            print(("MODEL POS: (%s, %s, %s)  ROT_RAD=(%.3f, %.3f, %.3f)"):format(fmt(px),fmt(py),fmt(pz), rx,ry,rz))
            lastCf = cf
        end
    end)
    print("spawn-castle: монитор запущен")
end

-- === main
local model = spawnModel(ASSET_ID)
if not model then return end

local targetCFrame = cframeFromPosRot(SPAWN_POS, SPAWN_ROT_DEG)
local ok = placeModel(model, targetCFrame, ANCHOR_PARTS)
if not ok then warn("spawn-castle: не удалось корректно разместить модель") end

print(("spawn-castle: модель '%s' заспавнена на %s ; rotDeg=(%s,%s,%s)"):
    format(model.Name, tostring(SPAWN_POS), fmt(SPAWN_ROT_DEG.X), fmt(SPAWN_ROT_DEG.Y), fmt(SPAWN_ROT_DEG.Z))
)

startMonitor(model)
