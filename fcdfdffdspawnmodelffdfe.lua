-- spawn_castle_fixed_simple.lua  (LocalScript, injector)
-- Спавнит модель (замок) по фиксированным координатам + опционально анкерит.
-- ID и координаты вверху — меняй при необходимости.

local Workspace = game:GetService("Workspace")

-- ========== НАСТРОЙКИ ==========
local ASSET_ID = "rbxassetid://128743514073638"  -- id замка
local TARGET_POS = Vector3.new(-28.000, 15.000, -4.000) -- координаты (x,y,z)
local TARGET_ROT_DEG = Vector3.new(0, -90.000, 0.000)   -- rotation (pitch,yaw,roll) в градусах
local ANCHOR_PARTS = true    -- true -> ставим Anchored = true для всех BasePart'ов
local ENABLE_MONITORING = false -- если true — печатает pos/rot модели в Output периодически
local MONITOR_INTERVAL = 0.25
-- =================================

local function fmt(n) return string.format("%.3f", tonumber(n) or 0) end

local function uniqueName(base)
    base = (base and tostring(base) ~= "" and tostring(base)) or "Model"
    local name = base
    local i = 1
    while Workspace:FindFirstChild(name) do
        i = i + 1
        name = base .. "_" .. tostring(i)
    end
    return name
end

local function findPrimaryPart(model)
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
    return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getModelCFrameForPlacement(model)
    -- Возвращает CFrame для установки: PrimaryPart или GetBoundingBox()
    if not model then return nil end
    local ok, cf = pcall(function()
        local prim = findPrimaryPart(model)
        if prim then return prim.CFrame end
        local bboxCf, _ = model:GetBoundingBox()
        return bboxCf
    end)
    return ok and cf or nil
end

local function setModelCFrame(model, desiredCFrame)
    if not model or not desiredCFrame then return end
    local prim = findPrimaryPart(model)
    if prim then
        pcall(function() model.PrimaryPart = prim end)
        pcall(function() model:SetPrimaryPartCFrame(desiredCFrame) end)
    else
        -- fallback: move each BasePart relative to model's bounding center
        local ok, bboxCf, size = pcall(function() return model:GetBoundingBox() end)
        if ok and bboxCf then
            local offset = desiredCFrame * bboxCf:Inverse()
            for _, p in ipairs(model:GetDescendants()) do
                if p:IsA("BasePart") then
                    pcall(function() p.CFrame = offset * p.CFrame end)
                end
            end
        end
    end
end

local function spawnModelNow()
    -- загрузка
    local ok, objs = pcall(function() return game:GetObjects(ASSET_ID) end)
    if not ok or not objs or #objs == 0 then
        warn("spawn_castle: не удалось загрузить asset:", ASSET_ID)
        return
    end

    local model = objs[1]:Clone()
    local baseName = model.Name or "Castle"
    model.Name = uniqueName(baseName)
    model.Parent = Workspace

    -- собираем CFrame назначения
    local rot = CFrame.Angles(math.rad(TARGET_ROT_DEG.X), math.rad(TARGET_ROT_DEG.Y), math.rad(TARGET_ROT_DEG.Z))
    local desiredCf = CFrame.new(TARGET_POS) * rot

    -- размещаем
    setModelCFrame(model, desiredCf)

    -- анкерим, обнуляем скорости (если нужно)
    if ANCHOR_PARTS then
        for _, p in ipairs(model:GetDescendants()) do
            if p:IsA("BasePart") then
                pcall(function()
                    p.Anchored = true
                    if p.AssemblyLinearVelocity then p.AssemblyLinearVelocity = Vector3.new(0,0,0) end
                    if p.AssemblyAngularVelocity then p.AssemblyAngularVelocity = Vector3.new(0,0,0) end
                end)
            end
        end
    end

    print(("spawn_castle: spawned '%s' at Pos=(%s,%s,%s) RotDeg=(%s,%s,%s)")
        :format(model.Name, fmt(TARGET_POS.X), fmt(TARGET_POS.Y), fmt(TARGET_POS.Z),
                fmt(TARGET_ROT_DEG.X), fmt(TARGET_ROT_DEG.Y), fmt(TARGET_ROT_DEG.Z))
    )

    -- опциональный мониторинг (необязательный)
    if ENABLE_MONITORING then
        local RunService = game:GetService("RunService")
        local lastCf = getModelCFrameForPlacement(model)
        local acc = 0
        RunService.Heartbeat:Connect(function(dt)
            acc = acc + dt
            if acc < MONITOR_INTERVAL then return end
            acc = 0
            local cf = getModelCFrameForPlacement(model)
            if cf then
                local pos = cf.Position
                local x,y,z = pos.X,pos.Y,pos.Z
                local rx,ry,rz = cf:ToEulerAnglesXYZ()
                print(string.format("MONITOR: Pos=(%s,%s,%s) RotDeg=(%s,%s,%s)",
                    fmt(x),fmt(y),fmt(z),
                    fmt(math.deg(rx)),fmt(math.deg(ry)),fmt(math.deg(rz))
                ))
            end
        end)
    end

    return model
end

spawnModelNow()
