-- watch-model-position.lua  (LocalScript, injector)
-- Наблюдает за моделью в workspace по имени и печатает позицию/ориентацию при изменениях.

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- === Настройки (редактируй) ===
local MODEL_NAME = "Castle"         -- <- имя модели в Workspace (замени на своё)
local POSITION_EPS = 0.001          -- минимальная дистанция (studs) для срабатывания
local ROTATION_DEG_EPS = 0.5        -- минимальное изменение ориентации (градусы) для срабатывания
local POLL_FALLBACK = true          -- включить резервный polling, если PropertyChanged не срабатывает
local POLL_INTERVAL = 0.05          -- интервал polling в секундах
-- ===============================

local function findModel()
    return Workspace:FindFirstChild(MODEL_NAME)
end

local function findPrimaryPart(model)
    if not model then return nil end
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
        return model.PrimaryPart
    end
    return model:FindFirstChildWhichIsA("BasePart", true)
end

local function cfToDegs(cf)
    local x,y,z = cf:ToOrientation() -- радианы
    return math.deg(x), math.deg(y), math.deg(z)
end

local function printCfInfo(prefix, cf)
    local pos = cf.Position
    local rx, ry, rz = cfToDegs(cf)
    local ts = string.format("%.2f", tick())
    print(("[WATCH] %s | t=%s | Pos=Vector3.new(%.6f, %.6f, %.6f) | RotDeg=Vector3.new(%.3f, %.3f, %.3f)"):format(prefix, ts, pos.X, pos.Y, pos.Z, rx, ry, rz))
    -- удобный сниппет для вставки в spawn-скрипт:
    print(("[SNIPPET] CFrame.new(%.6f, %.6f, %.6f) * CFrame.Angles(math.rad(%.6f), math.rad(%.6f), math.rad(%.6f))"):format(
        pos.X, pos.Y, pos.Z, rx, ry, rz))
end

-- сравнение поз/ротаций
local function hasSignificantChange(lastPos, lastRotDeg, newPos, newRotDeg)
    if not lastPos or not lastRotDeg then return true end
    if (newPos - lastPos).Magnitude > POSITION_EPS then return true end
    local dx = math.abs(newRotDeg.X - lastRotDeg.X)
    local dy = math.abs(newRotDeg.Y - lastRotDeg.Y)
    local dz = math.abs(newRotDeg.Z - lastRotDeg.Z)
    if dx > ROTATION_DEG_EPS or dy > ROTATION_DEG_EPS or dz > ROTATION_DEG_EPS then return true end
    return false
end

-- основной наблюдатель
do
    local model = findModel()
    if not model then
        warn(("watch-model-position: модель '%s' не найдена в workspace. Проверь MODEL_NAME."):format(MODEL_NAME))
    end

    local primary = model and findPrimaryPart(model)
    local lastPos, lastRotDeg = nil, nil
    local propConn = nil
    local pollAcc = 0

    local function handleCF(cf)
        if not cf then return end
        local pos = cf.Position
        local rx, ry, rz = cfToDegs(cf)
        local newRot = Vector3.new(rx, ry, rz)
        if hasSignificantChange(lastPos, lastRotDeg, pos, newRot) then
            printCfInfo(model and model.Name or MODEL_NAME, cf)
            lastPos = pos
            lastRotDeg = newRot
        end
    end

    local function attachToPrimary(p)
        if not p then return end
        -- initial snapshot
        pcall(function() handleCF(p.CFrame) end)
        -- disconnect old
        if propConn then pcall(function() propConn:Disconnect() end) end
        -- try property changed signal
        local ok, conn = pcall(function() return p:GetPropertyChangedSignal("CFrame") end)
        if ok and conn then
            propConn = conn:Connect(function()
                pcall(function() handleCF(p.CFrame) end)
            end)
            print("[watch-model] connected to PrimaryPart:GetPropertyChangedSignal('CFrame')")
        else
            propConn = nil
            print("[watch-model] property signal unavailable; will rely on polling fallback")
        end
    end

    if primary then
        attachToPrimary(primary)
    end

    -- RenderStepped polling as fallback + auto reattach if model/primary changes
    local lastModelRef = model
    RunService.RenderStepped:Connect(function(dt)
        -- auto-find model if it's not found or was replaced
        model = model or findModel()
        if model ~= lastModelRef then
            lastModelRef = model
            primary = findPrimaryPart(model)
            if propConn then pcall(function() propConn:Disconnect() end); propConn = nil end
            lastPos, lastRotDeg = nil, nil
            if model then
                print("[watch-model] detected model added/changed:", model.Name)
            end
            if primary then
                attachToPrimary(primary)
            end
        end

        if primary and propConn then
            -- property-driven path already handles changes
            return
        end

        -- polling fallback
        if POLL_FALLBACK and primary then
            pollAcc = pollAcc + dt
            if pollAcc >= POLL_INTERVAL then
                pollAcc = 0
                local ok, cf = pcall(function() return primary.CFrame end)
                if ok and cf then handleCF(cf) end
            end
        end
    end)
end

print("[watch-model] ready. Отслеживает модель: " .. tostring(MODEL_NAME))
