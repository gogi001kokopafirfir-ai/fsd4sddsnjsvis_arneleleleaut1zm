-- combined-hide-character-and-effects.lua
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local lp = Players.LocalPlayer

local HIDE_RIGHT_ARM_PART = false  -- Установите true, чтобы скрыть RightArmPart (по умолчанию false — видим)

-- Начало первого скрипта (скрытие частей персонажа с исключениями)
local function isException(part)
    -- Исключения: RightArmPart и ToolHandle (и их потомки)
    if (part.Name == "RightArmPart" and not HIDE_RIGHT_ARM_PART) or part.Name == "ToolHandle" then
        return true
    end
    -- Проверяем родителей для потомков
    local parent = part.Parent
    while parent do
        if parent.Name == "ToolHandle" or (parent.Name == "RightArmPart" and not HIDE_RIGHT_ARM_PART) then
            return true
        end
        parent = parent.Parent
    end
    return false
end

local function hidePart(part)
    if part:IsA("BasePart") and not isException(part) then
        part.LocalTransparencyModifier = 1
    elseif part:IsA("Decal") then  -- Специально для декалей лица
        part.LocalTransparencyModifier = 1
    end
end

local function hideCharacter(char)
    if not char then return end

    -- Скрываем существующие части
    for _, descendant in ipairs(char:GetDescendants()) do
        hidePart(descendant)
    end

    -- Слушаем добавление новых частей (броня, инструменты и т.д.)
    char.DescendantAdded:Connect(function(child)
        hidePart(child)
        -- Если добавлен Tool, слушаем Equipped/UnEquipped для переустановки
        if child:IsA("Tool") then
            child.Equipped:Connect(function()
                wait()  -- Короткая задержка для загрузки ToolHandle
                for _, desc in ipairs(char:GetDescendants()) do
                    hidePart(desc)
                end
            end)
            child.Unequipped:Connect(function()
                wait()
                for _, desc in ipairs(char:GetDescendants()) do
                    hidePart(desc)
                end
            end)
        end
    end)

    -- Цикл для переустановки видимости при смене FP/TP (RenderStepped минимальный)
    local conn = RunService.RenderStepped:Connect(function()
        for _, descendant in ipairs(char:GetDescendants()) do
            hidePart(descendant)
        end
    end)
    -- Отключение при респауне (будет пересоздано в CharacterAdded)
    char.AncestryChanged:Connect(function()
        if conn then conn:Disconnect() end
    end)
end
-- Конец первого скрипта

-- Начало второго скрипта (скрытие эффектов)
local function hideEffects(char)
    local hrp = char:WaitForChild("HumanoidRootPart")
    local torso = char:WaitForChild("Torso") or char:WaitForChild("UpperTorso")  -- R6/R15 support
    local head = char:WaitForChild("Head")  -- For face decals

    local function hideChild(child)
        if child:IsA("Highlight") then
            child.Enabled = false  -- Disable Highlight completely
            child.FillTransparency = 1
            child.OutlineTransparency = 1
        elseif child:IsA("ParticleEmitter") and (child.Name == "Ashes" or child.Name:match("Fire") or child.Name:match("Smoke") or child.Name == "Poison" or child.Name == "FrozenAura") then
            child.Enabled = false
        elseif child:IsA("PointLight") then
            child.Enabled = false
        elseif child:IsA("Decal") and child.Parent == head then  -- Hide face decal if used in effects
            child.LocalTransparencyModifier = 1
        end
    end

    -- Hide existing effects
    for _, c in ipairs(char:GetDescendants()) do
        hideChild(c)
    end

    -- Listen for new effects
    char.DescendantAdded:Connect(hideChild)
end
-- Конец второго скрипта

-- Общие вызовы для текущего персонажа и респауна (вызываем обе функции)
local function applyBoth(char)
    hideCharacter(char)  -- Первый скрипт
    hideEffects(char)    -- Второй скрипт
end

if lp.Character then
    applyBoth(lp.Character)
end

lp.CharacterAdded:Connect(applyBoth)
