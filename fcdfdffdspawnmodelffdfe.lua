-- spawn_static_from_asset.lua
-- Загружает статичную модель (мебель/дом) по asset id, удаляет скрипты и размещает локальную копию в workspace на земле.
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

-- Настройки (изменяйте здесь)
local ASSET_ID = 8959904556 -- <- Замени на свой asset id (число)
local ACTIVATION_KEY = Enum.KeyCode.R -- Клавиша для добавления (R по умолчанию)
local SPAWN_DISTANCE = 8 -- На какое расстояние перед камерой спавнить
local SPAWN_HEIGHT_OFFSET = 5 -- Высота для raycast (чтобы найти землю)

local function sanitizeModel(model)
    for _, v in ipairs(model:GetDescendants()) do
        if v:IsA("Script") or v:IsA("LocalScript") or v:IsA("ModuleScript") then
            pcall(function() v:Destroy() end)
        end
        if v:IsA("BasePart") then
            pcall(function()
                v.CanCollide = false -- Не мешать взаимодействию (измените на true если нужно столкновения)
                v.Anchored = true -- Для статичных моделей — фиксировать на месте
            end)
        end
    end
    -- Если нужно — добавьте дополнительные чистки (RemoteEvent и т.д.)
end

local function getUniqueName(baseName)
    local name = baseName
    local counter = 1
    while Workspace:FindFirstChild(name) do
        name = baseName .. tostring(counter)
        counter = counter + 1
    end
    return name
end

local function spawnFromAsset(assetId)
    local ok, objs = pcall(function() return game:GetObjects("rbxassetid://" .. tostring(assetId)) end)
    if not ok or not objs or #objs == 0 then
        warn("Не удалось загрузить asset id:", assetId)
        return nil
    end
    local model = objs[1]
    if not model or not model:IsA("Model") then
        warn("Загруженный asset не является моделью")
        return nil
    end

    -- Получаем уникальное имя на основе оригинального
    local uniqueName = getUniqueName(model.Name)
    model.Name = uniqueName

    sanitizeModel(model)

    -- Выставим PrimaryPart и позиционируем перед камерой на земле
    local prim = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    if prim and Workspace.CurrentCamera then
        -- Raycast для поиска земли
        local camCFrame = Workspace.CurrentCamera.CFrame
        local rayOrigin = camCFrame.Position + camCFrame.LookVector * SPAWN_DISTANCE + Vector3.new(0, SPAWN_HEIGHT_OFFSET, 0)
        local rayDirection = Vector3.new(0, -100, 0) -- Вниз
        local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = {Players.LocalPlayer.Character or {}}
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.IgnoreWater = true

        local rayResult = Workspace:Raycast(rayOrigin, rayDirection, rayParams)
        if rayResult then
            prim.CFrame = CFrame.new(rayResult.Position) * CFrame.new(0, model:GetExtentsSize().Y / 2, 0) -- Центр на земле
        else
            prim.CFrame = camCFrame * CFrame.new(0, 0, -SPAWN_DISTANCE) -- Fallback
        end
        model.PrimaryPart = prim
    end

    model.Parent = Workspace
    print("[spawn_from_asset] spawned:", model:GetFullName())
    return model
end

-- Слушаем клавишу для повторного добавления (не удаляем предыдущие)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    if input.KeyCode == ACTIVATION_KEY then
        spawnFromAsset(ASSET_ID)
    end
end)
