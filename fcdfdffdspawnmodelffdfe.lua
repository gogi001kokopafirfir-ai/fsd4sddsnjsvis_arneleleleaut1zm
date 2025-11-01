-- spawn-fixed-castle-with-monitor.lua  (LocalScript, injector)
-- Спавнит модель по ID и (опционально) мониторит её позицию/ориентацию в реальном времени.
-- Используйте F3X / Dex чтобы передвинуть модель — координаты будут печататься в консоль.

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

-- ========================
-- =  Конфигурация  (редактируйте) =
-- ========================
local ASSET_ID = "rbxassetid://128743514073638" -- <- ID модели (замка)
local FIXED_POSITION = Vector3.new(0, 5, 0)      -- стартовая позиция (X,Y,Z)
local ROTATION_DEG    = Vector3.new(0, 0, 0)     -- стартовый поворот (pitch, yaw, roll) в градусах
local ANCHOR_PLACED_MODEL = true                 -- анкерить модель после размещения
local ALIGN_TO_GROUND = false                    -- пытаться выставить низ модели на FIXED_POSITION.Y

-- Мониторинг (если true — начинает слушать изменения и печатать в консоль)
local ENABLE_MONITORING = true
local MONITOR_INTERVAL = 0.12    -- сек (частота проверки)
local POS_CHANGE_THRESHOLD = 0.02 -- минимальное изменение позиции (в студз) для логирования
local ANGLE_CHANGE_THRESHOLD_DEG = 1.0 -- минимальное изменение угла (в градусах) для логирования
-- ========================

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

local function findPrimaryPart(model)
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
    return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getLowestY(model)
    local minY = math.huge
    local found = false
    for _,d in ipairs(model:GetDescendants()) do
        if d:IsA("BasePart") then
            found = true
            local bottom = d.Position.Y - (d.Size.Y/2)
            if bottom < minY then minY = bottom end
        end
    end
    return found and minY or nil
end

local function spawnAssetById(assetIdStr)
    if not assetIdStr or assetIdStr == "" then
        warn("spawn-fixed: empty asset id")
        return nil
    end
    local ok, objs = pcall(function() return game:GetObjects(assetIdStr) end)
    if not ok or not objs or #objs == 0 then
        warn("spawn-fixed: GetObjects failed for", assetIdStr)
        return nil
    end
    -- objs[1] обычно Model
    local model = objs[1]:Clone()
    return model
end

local function placeModelAt(model, posVec3, rotationDeg, anchorPlaced, alignToGround)
    if not model then return end
    local prim = findPrimaryPart(model)
    if prim then model.PrimaryPart = prim end

    local rotCFrame = CFrame.Angles(math.rad(rotationDeg.X), math.rad(rotationDeg.Y), math.rad(rotationDeg.Z))

    if alignToGround then
        local lowest = getLowestY(model)
        if lowest and prim then
            local delta = prim.Position.Y - lowest -- высота от prim до низа модели
            local desiredY = posVec3.Y + delta
            local basePos = Vector3.new(posVec3.X, desiredY, posVec3.Z)
            local baseCFrame = CFrame.new(basePos) * rotCFrame
            pcall(function()
                if not model.Parent then model.Parent = Workspace end
                model:SetPrimaryPartCFrame(baseCFrame)
            end)
        else
            if prim then
                pcall(function() prim.CFrame = CFrame.new(posVec3) * rotCFrame end)
            else
                pcall(function() model:SetPrimaryPartCFrame(CFrame.new(posVec3) * rotCFrame) end)
            end
        end
    else
        if prim then
            pcall(function() prim.CFrame = CFrame.new(posVec3) * rotCFrame end)
        else
            pcall(function() model:SetPrimaryPartCFrame(CFrame.new(posVec3) * rotCFrame) end)
        end
    end

    for _, part in ipairs(model:GetDescendants()) do
        if part:IsA("BasePart") then
            pcall(function()
                part.Anchored = anchorPlaced
                if anchorPlaced and part.AssemblyLinearVelocity then
                    part.AssemblyLinearVelocity = Vector3.new(0,0,0)
                    part.AssemblyAngularVelocity = Vector3.new(0,0,0)
                end
            end)
        end
    end
end

-- Утилита: формат вывода (3 знака)
local function fmt(n) return string.format("%.3f", tonumber(n) or 0) end

-- Получить "репрезентативный" CFrame модели:
-- сначала пробуем модель:GetPrimaryPartCFrame(), затем Model:GetBoundingBox()
local function getModelCFrame(model)
    if not model then return nil end
    local ok, cf = pcall(function()
        if model.PrimaryPart then
            return model:GetPrimaryPartCFrame()
        else
            -- GetBoundingBox возвращает (CFrame, size)
            local bboxCf, size = model:GetBoundingBox()
            return bboxCf
        end
    end)
    if ok and cf then return cf end
    return nil
end

-- Преобразовать CFrame -> Euler XYZ в градусах
local function cframeToEulerDeg(cf)
    if not cf then return 0,0,0 end
    local ok, x, y, z = pcall(function() return cf:ToEulerAnglesXYZ() end)
    if not ok then return 0,0,0 end
    return math.deg(x), math.deg(y), math.deg(z)
end

-- Мониторинг: сравнить позицию/углы с порогами
local function startMonitoringModel(model)
    if not model then return end
    local lastCf = getModelCFrame(model)
    if not lastCf then
        warn("monitor: cannot get initial model CFrame")
        return
    end
    local lastPos = lastCf.Position
    local lx, ly, lz = cframeToEulerDeg(lastCf)

    local accTime = 0
    local conn
    conn = RunService.Heartbeat:Connect(function(dt)
        accTime = accTime + dt
        if accTime < MONITOR_INTERVAL then return end
        accTime = 0

        local cf = getModelCFrame(model)
        if not cf then
            -- модель могла быть удалена
            conn:Disconnect()
            print("monitor: model removed, stopping monitor")
            return
        end
        local pos = cf.Position
        local px,py,pz = pos.X, pos.Y, pos.Z
        local dx = (pos - lastPos).Magnitude

        local ax, ay, az = cframeToEulerDeg(cf)
        local da = math.max(math.abs(ax - lx), math.abs(ay - ly), math.abs(az - lz))

        if dx >= POS_CHANGE_THRESHOLD or da >= ANGLE_CHANGE_THRESHOLD_DEG then
            -- печатаем читаемый формат: позиция и углы (pitch,yaw,roll)
            print(string.format("MODEL MOVED: Pos=(%s, %s, %s) RotDeg=(%s, %s, %s)",
                fmt(px), fmt(py), fmt(pz),
                fmt(ax), fmt(ay), fmt(az)
            ))
            lastPos = pos
            lx, ly, lz = ax, ay, az
        end
    end)

    print("monitor: started for model:", model.Name)
end

-- Main flow
local function spawnFixed()
    local model = spawnAssetById(ASSET_ID)
    if not model then return end

    local baseName = model.Name or "Model"
    local finalName = uniqueName(baseName)
    model.Name = finalName

    model.Parent = Workspace

    placeModelAt(model, FIXED_POSITION, ROTATION_DEG, ANCHOR_PLACED_MODEL, ALIGN_TO_GROUND)

    print(("spawn-fixed: spawned '%s' at (%.3f, %.3f, %.3f)"):format(finalName, FIXED_POSITION.X, FIXED_POSITION.Y, FIXED_POSITION.Z))

    if ENABLE_MONITORING then
        -- небольшая задержка чтобы F3X успел "подхватить" модель и PrimaryPart определился
        delay(0.15, function()
            -- убедимся, что у модели есть PrimaryPart либо GetBoundingBox сможет вернуть CFrame
            local ok = pcall(function() if not findPrimaryPart(model) then local bbox = model:GetBoundingBox() end end)
            if not model.Parent then return end
            startMonitoringModel(model)
        end)
    end
end

spawnFixed()
