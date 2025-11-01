-- spawn-fixed-castle.lua  (LocalScript, injector)
-- Спавнит модель (замок) по фиксированным координатам (локально для игрока).
-- Конфигурация вверху: поменяй ASSET_ID, FIXED_POSITION, ROTATION_DEG, ANCHOR_PLACED_MODEL, ALIGN_TO_GROUND.

local workspace = game:GetService("Workspace")

-- ========================
-- = Настройки (редактируйте) =
-- ========================
local ASSET_ID = "rbxassetid://128743514073638" -- <-- ID замка
-- Начальное фиксированное место (по умолчанию — центр карты). Меняйте на нужные координаты.
local FIXED_POSITION = Vector3.new(0, 5, 0)      -- X, Y, Z (Y = высота, можно потом подправить)
-- Ориентация (в градусах) — модель повернута относительно forward.
local ROTATION_DEG = Vector3.new(0, 0, 0)       -- pitch, yaw, roll (deg)
local ANCHOR_PLACED_MODEL = true                -- заанкерить модель после размещения (стабильность)
local ALIGN_TO_GROUND = false                   -- если true: попытается подогнать низ модели по FIXED_POSITION.Y
-- Если ALIGN_TO_GROUND = true, то FIXED_POSITION.Y трактуется как абсолютная высота земли (низ модели будет на этой Y).
-- ========================

-- Утилиты
local function uniqueName(base)
    if not base or base == "" then base = "Model" end
    local name = base
    local i = 1
    while workspace:FindFirstChild(name) do
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
    -- клонируем загруженный объект (обычно objs[1] — Model)
    local model = objs[1]:Clone()
    return model
end

local function placeModelAt(model, posVec3, rotationDeg, anchorPlaced, alignToGround)
    if not model then return end
    -- сбор PrimaryPart
    local prim = findPrimaryPart(model)
    if prim then model.PrimaryPart = prim end

    -- вычисляем желаемую CFrame
    local rot = CFrame.Angles(math.rad(rotationDeg.X), math.rad(rotationDeg.Y), math.rad(rotationDeg.Z))

    if alignToGround then
        -- если можем определить lowestY модели — поднимем/опустим так, чтобы низ совпал с posVec3.Y
        local lowest = getLowestY(model)
        if lowest and prim then
            local delta = prim.Position.Y - lowest -- от primary до низа
            local desiredY = posVec3.Y + delta
            local basePos = Vector3.new(posVec3.X, desiredY, posVec3.Z)
            local baseCFrame = CFrame.new(basePos) * rot
            pcall(function()
                -- временно parent чтобы SetPrimaryPartCFrame работал корректно
                if not model.Parent then model.Parent = workspace end
                model:SetPrimaryPartCFrame(baseCFrame)
            end)
        else
            -- fallback: ставим primary в posVec3
            if prim then
                pcall(function() prim.CFrame = CFrame.new(posVec3) * rot end)
            else
                pcall(function() model:SetPrimaryPartCFrame(CFrame.new(posVec3) * rot) end)
            end
        end
    else
        -- строго по FIXED_POSITION: primary в posVec3 (ориентация применяется)
        if prim then
            pcall(function() prim.CFrame = CFrame.new(posVec3) * rot end)
        else
            pcall(function() model:SetPrimaryPartCFrame(CFrame.new(posVec3) * rot) end)
        end
    end

    -- Anchor / physics tweak
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

-- Main: spawn once (без клавиш)
local function spawnFixed()
    local model = spawnAssetById(ASSET_ID)
    if not model then return end

    -- имя — используем имя модели из ассета, но делаем уникальным
    local baseName = model.Name or "Castle"
    local finalName = uniqueName(baseName)
    model.Name = finalName

    -- parent в workspace (до позиционирования — чтобы SetPrimaryPartCFrame работал)
    model.Parent = workspace

    placeModelAt(model, FIXED_POSITION, ROTATION_DEG, ANCHOR_PLACED_MODEL, ALIGN_TO_GROUND)

    print(("spawn-fixed: spawned '%s' at (%.1f, %.1f, %.1f)"):format(finalName, FIXED_POSITION.X, FIXED_POSITION.Y, FIXED_POSITION.Z))
end

-- Запуск
spawnFixed()
