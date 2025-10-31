-- spawn-model-near-player.lua (LocalScript)
-- Добавляет модель по asset id рядом с игроком и ставит на землю.
-- Конфигурация вверху: меняйте ASSET_ID, DISTANCE, ANCHOR_PLACED_MODEL и т.д.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local workspace = game:GetService("Workspace")

local lp = Players.LocalPlayer
if not lp then warn("SpawnModel: no LocalPlayer") return end

-- =======================
-- Настройки (редактируйте здесь)
-- =======================
local ASSET_ID = "rbxassetid://75011024682680"  -- <-- поставьте нужный rbxassetid://...
local SPAWN_DISTANCE = 6                         -- от игрока по направлению взгляда (studs)
local SPAWN_HEIGHT_ABOVE = 6                     -- высота над землёй для начального луча (studs)
local DROP_RAY_LENGTH = 200                      -- насколько вниз кастить луч для поиска земли
local FACE_TO_PLAYER = true                      -- пусть модель будет повернута лицом к игроку
local ANCHOR_PLACED_MODEL = true                 -- заанкерить модель после спавна (стабильность)
local NAME_PREFIX = nil                          -- если nil — будет имя модели из ассета; иначе фиксированное префикс-имя
local SPAWN_KEY = Enum.KeyCode.G                 -- клавиша для повторного спавна в сессии
-- =======================

-- утилиты
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

local function getLowestY(model)
    if not model then return nil end
    local minY = math.huge
    local found = false
    for _,inst in ipairs(model:GetDescendants()) do
        if inst:IsA("BasePart") then
            found = true
            local bottom = inst.Position.Y - (inst.Size.Y/2)
            if bottom < minY then minY = bottom end
        end
    end
    return found and minY or nil
end

local function findPrimaryPart(model)
    if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then return model.PrimaryPart end
    -- Поиск первой BasePart (глубокий)
    local p = model:FindFirstChildWhichIsA("BasePart", true)
    return p
end

local function placeModelOnPoint(model, targetPoint, faceToPos)
    -- targetPoint = Vector3 где хотим чтобы нижняя поверхность модели соприкасалась с землёй
    -- faceToPos optional Vector3 — точка, к которой нужно повернуть модель лицом
    if not model then return end
    local prim = findPrimaryPart(model)
    if not prim then
        warn("SpawnModel: no basepart in model; placing at target point without alignment")
        model.PrimaryPart = nil
        model:SetPrimaryPartCFrame(CFrame.new(targetPoint))
        return
    end
    model.PrimaryPart = prim

    -- вычислим lowestY модели, чтобы поставить модель так, чтобы низ совпал с targetPoint.Y
    local lowest = getLowestY(model)
    if lowest then
        local delta = prim.Position.Y - lowest -- расстояние от primaryPart до низа
        local desiredY = targetPoint.Y + delta
        local basePos = Vector3.new(targetPoint.X, desiredY, targetPoint.Z)
        local baseCFrame = CFrame.new(basePos)
        if faceToPos then
            -- направим forward модели так, чтобы её lookVector смотрел на faceToPos - basePos
            local lookDir = (Vector3.new(faceToPos.X, basePos.Y, faceToPos.Z) - basePos)
            if lookDir.Magnitude > 0.001 then
                baseCFrame = CFrame.new(basePos, basePos + lookDir)
            end
        end
        -- Применяем
        prim.Parent = model
        -- Важный момент: некоторые модели содержат Motor6D и связи — лучше временно отключить физику у частей
        for _, part in ipairs(model:GetDescendants()) do
            if part:IsA("BasePart") then
                pcall(function()
                    part.Anchored = ANCHOR_PLACED_MODEL
                    -- не меняем CanCollide здесь — пользователь захочет взаимодействие в некоторых моделях
                end)
            end
        end
        pcall(function() model:SetPrimaryPartCFrame(baseCFrame) end)
    else
        -- если нет частей — просто позиционируем PrimaryPart в targetPoint
        pcall(function() model:SetPrimaryPartCFrame(CFrame.new(targetPoint)) end)
    end
end

local function raycastDown(fromPos)
    local rayOrigin = fromPos
    local rayDest = fromPos - Vector3.new(0, DROP_RAY_LENGTH, 0)
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = { } -- по умолчанию не фильтруем
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.IgnoreWater = true
    local result = workspace:Raycast(rayOrigin, rayDest - rayOrigin, rayParams)
    return result
end

local function spawnAssetById(assetIdStr)
    if not assetIdStr or assetIdStr == "" then warn("SpawnModel: empty asset id") return nil end
    local ok, objs = pcall(function() return game:GetObjects(assetIdStr) end)
    if not ok or not objs or #objs == 0 then
        warn("SpawnModel: failed to GetObjects for", assetIdStr)
        return nil
    end
    -- чаще всего первый элемент — Model
    local loaded = objs[1]:Clone()
    return loaded
end

local function spawnModelNow(assetIdStr)
    local char = lp.Character
    if not char then warn("SpawnModel: no character") return end
    local hrp = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
    if not hrp then warn("SpawnModel: no HRP/PrimaryPart") return end

    local model = spawnAssetById(assetIdStr)
    if not model then return end

    -- name handling
    local baseName = NAME_PREFIX
    if not baseName then
        baseName = model.Name or "Model"
    end
    local finalName = uniqueName(baseName)
    model.Name = finalName

    -- compute spawn base position: в направлении взгляда камеры (или HRP lookVector)
    local lookVector = workspace.CurrentCamera and workspace.CurrentCamera.CFrame.LookVector or hrp.CFrame.LookVector
    local spawnCenter = hrp.Position + (lookVector.Unit * SPAWN_DISTANCE) + Vector3.new(0, SPAWN_HEIGHT_ABOVE, 0)

    -- raycast вниз, если нашли поверхность, используем hit.Position as ground Y
    local hit = raycastDown(spawnCenter)
    local groundY = nil
    if hit and hit.Position then
        groundY = hit.Position.Y
    else
        -- fallback — возьмём высоту персонажа - 1.5
        groundY = hrp.Position.Y - 2
    end

    local targetPoint = Vector3.new(spawnCenter.X, groundY, spawnCenter.Z)

    -- Parent model into workspace BEFORE positioning (важно, чтобы :SetPrimaryPartCFrame работал корректно)
    model.Parent = workspace

    -- если модель не имеет PrimaryPart — попытаемся найти любую BasePart и назначить
    local prim = findPrimaryPart(model)
    if prim then
        model.PrimaryPart = prim
    end

    -- Если FACE_TO_PLAYER, то повернём модель лицом к игроку
    local faceTo = nil
    if FACE_TO_PLAYER then
        faceTo = hrp.Position
    end

    placeModelOnPoint(model, targetPoint, faceTo)

    print(("SpawnModel: placed '%s' from %s at (%.2f, %.2f, %.2f)"):format(finalName, assetIdStr, targetPoint.X, targetPoint.Y, targetPoint.Z))
    return model
end

-- сразу спавним один раз (при старте)
pcall(function() spawnModelNow(ASSET_ID) end)

-- биндим клавишу SPAWN_KEY для повторного спавна
UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == SPAWN_KEY then
        spawnModelNow(ASSET_ID)
    end
end)

print("SpawnModel: ready. Initial ASSET_ID =", ASSET_ID, "Press", SPAWN_KEY.Name, "to spawn again.")
