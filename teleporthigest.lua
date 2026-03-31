-- ============================================================
-- CLOUD HUB TP - UNIVERSAL EDITION
-- ============================================================
-- Premium Teleport System from Brainrot Script
-- Auto-detects Mobile/PC | Bottom-Right Position
-- ============================================================

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer

-- ============================================================
-- DEVICE DETECTION
-- ============================================================
local isMobile = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
local isTablet = UserInputService.TouchEnabled and workspace.CurrentCamera.ViewportSize.X >= 768
local isDesktop = not UserInputService.TouchEnabled or UserInputService.MouseEnabled
local deviceType = isMobile and "MOBILE" or (isTablet and "TABLET" or "DESKTOP")

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
    SAFE_TELEPORT = true,
    FAVORITES_PRIORITY = false,
    REFRESH_INTERVAL = 3,
}

-- ============================================================
-- SERVICES
-- ============================================================
local S = {
    Players = Players,
    TweenService = TweenService,
    ReplicatedStorage = ReplicatedStorage,
}
S.Packages = S.ReplicatedStorage:WaitForChild("Packages")
S.Datas = S.ReplicatedStorage:WaitForChild("Datas")
S.Shared = S.ReplicatedStorage:WaitForChild("Shared")
S.Utils = S.ReplicatedStorage:WaitForChild("Utils")

S.Synchronizer = require(S.Packages:WaitForChild("Synchronizer"))
S.AnimalsData = require(S.Datas:WaitForChild("Animals"))
S.AnimalsShared = require(S.Shared:WaitForChild("Animals"))
S.NumberUtils = require(S.Utils:WaitForChild("NumberUtils"))

-- ============================================================
-- COLORS
-- ============================================================
local COLORS = {
    BG = Color3.fromRGB(15, 20, 35),
    Surface = Color3.fromRGB(25, 32, 50),
    Cloud = Color3.fromRGB(100, 150, 255),
    CloudLight = Color3.fromRGB(135, 180, 255),
    Text = Color3.fromRGB(255, 255, 255),
    Dim = Color3.fromRGB(180, 190, 220),
    Green = Color3.fromRGB(100, 255, 150),
    Red = Color3.fromRGB(255, 100, 120),
    Yellow = Color3.fromRGB(255, 220, 100),
    Cyan = Color3.fromRGB(0, 200, 255),
    Warning = Color3.fromRGB(255, 200, 100),
}

-- ============================================================
-- GLOBALS
-- ============================================================
local allAnimalsCache = {}
local FAVORITES = {}
local screenGui = nil
local mainFrame = nil
local minimized = false
local searchBox = nil
local animalListFrame = nil
local searchQuery = ""

-- ============================================================
-- PREMIUM TELEPORT SYSTEM (aus Brainrot Script)
-- ============================================================

local function getHRP()
    local char = LP.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("UpperTorso")
end

local function getSideBounds(sideFolder)
    if not sideFolder then return nil end
    
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
    local found = false
    
    local function scan(obj)
        for _, child in ipairs(obj:GetChildren()) do
            if child:IsA("BasePart") then
                found = true
                local p = child.Position
                minX = math.min(minX, p.X)
                minY = math.min(minY, p.Y)
                minZ = math.min(minZ, p.Z)
                maxX = math.max(maxX, p.X)
                maxY = math.max(maxY, p.Y)
                maxZ = math.max(maxZ, p.Z)
            else
                scan(child)
            end
        end
    end
    
    scan(sideFolder)
    if not found then return nil end
    
    local center = Vector3.new((minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5)
    local halfSize = Vector3.new((maxX - minX) * 0.5, (maxY - minY) * 0.5, (maxZ - minZ) * 0.5)
    
    return {
        center = center,
        halfSize = halfSize,
        minX = minX,
        maxX = maxX,
        minZ = minZ,
        maxZ = maxZ,
    }
end

local function getSafeOutsideDecorPos(plot, targetPos, fromPos)
    local decorations = plot:FindFirstChild("Decorations")
    if not decorations then return targetPos end
    
    local side3Folder = decorations:FindFirstChild("Side 3")
    if not side3Folder then return targetPos end
    
    local info = getSideBounds(side3Folder)
    if not info then return targetPos end
    
    local center = info.center
    local halfSize = info.halfSize
    local MARGIN = 4
    
    local localTarget = targetPos - center
    local insideX = math.abs(localTarget.X) <= halfSize.X
    local insideZ = math.abs(localTarget.Z) <= halfSize.Z
    
    if not (insideX and insideZ) then
        return targetPos
    end
    
    local src = fromPos and (fromPos - center) or localTarget
    local dir = Vector3.new(src.X, 0, src.Z)
    
    if dir.Magnitude < 1e-3 then
        dir = Vector3.new(0, 0, 1)
    end
    
    local dirUnit = dir.Unit
    local tx, tz = math.huge, math.huge
    
    if dirUnit.X ~= 0 then
        local boundX = (dirUnit.X > 0) and halfSize.X or -halfSize.X
        tx = boundX / dirUnit.X
    end
    
    if dirUnit.Z ~= 0 then
        local boundZ = (dirUnit.Z > 0) and halfSize.Z or -halfSize.Z
        tz = boundZ / dirUnit.Z
    end
    
    local tHit = math.min(tx, tz)
    if tHit == math.huge then return targetPos end
    
    local boundaryLocal = dirUnit * (tHit + MARGIN)
    local worldPos = center + boundaryLocal
    
    return Vector3.new(worldPos.X, targetPos.Y, worldPos.Z)
end

local function getSmartCarpetPosition(carpetPart, fromPos)
    if not carpetPart or not fromPos then return nil end
    
    local cf = carpetPart.CFrame
    local size = carpetPart.Size
    local halfX = size.X / 2
    local halfZ = size.Z / 2
    
    local localPos = cf:PointToObjectSpace(fromPos)
    local clampedX = math.clamp(localPos.X, -halfX, halfX)
    local clampedZ = math.clamp(localPos.Z, -halfZ, halfZ)
    
    if math.abs(localPos.X) < halfX and math.abs(localPos.Z) < halfZ then
        local distToEdges = {
            north = halfZ - localPos.Z,
            south = halfZ + localPos.Z,
            east = halfX - localPos.X,
            west = halfX + localPos.X
        }
        
        local minDist = math.huge
        local nearestEdge = "north"
        
        for edge, dist in pairs(distToEdges) do
            if dist < minDist then
                minDist = dist
                nearestEdge = edge
            end
        end
        
        if nearestEdge == "north" then
            clampedZ = halfZ
        elseif nearestEdge == "south" then
            clampedZ = -halfZ
        elseif nearestEdge == "east" then
            clampedX = halfX
        else
            clampedX = -halfX
        end
    end
    
    local nearestPoint = cf:PointToWorldSpace(Vector3.new(clampedX, 0, clampedZ))
    
    local rayOrigin = nearestPoint + Vector3.new(0, 50, 0)
    local rayParams = RaycastParams.new()
    rayParams.FilterDescendantsInstances = { workspace.Map }
    rayParams.FilterType = Enum.RaycastFilterType.Whitelist
    
    local result = workspace:Raycast(rayOrigin, Vector3.new(0, -100, 0), rayParams)
    local finalY = result and result.Position.Y or fromPos.Y
    
    return Vector3.new(nearestPoint.X, finalY, nearestPoint.Z)
end

local function tpNearPlotIfFar(animalData)
    local hrp = getHRP()
    if not hrp or not animalData or not animalData.plot then return end

    local plot = workspace.Plots:FindFirstChild(animalData.plot)
    if not plot then return end

    local plotPos = plot:GetPivot().Position

    if (hrp.Position - plotPos).Magnitude <= 100 then
        return
    end

    local decorations = plot:FindFirstChild("Decorations")
    local side3 = decorations and decorations:FindFirstChild("Side 3") or nil
    local info = side3 and getSideBounds(side3) or nil
    local center = info and info.center or plotPos

    local dir = (hrp.Position - center).Unit
    local distanceFromPlot = 70
    local y = center.Y + 4

    local finalPos = Vector3.new(
        center.X + dir.X * distanceFromPlot,
        y,
        center.Z + dir.Z * distanceFromPlot
    )

    hrp.CFrame = CFrame.new(finalPos, center)
end

-- HAUPT-TELEPORT-FUNKTION (Premium Version)
local function teleportToAnimal(animalData)
    local character = LP.Character
    if not character or not character:FindFirstChild("HumanoidRootPart") then
        return false
    end
    
    local humanoid = character:FindFirstChild("Humanoid")
    local hrp = character.HumanoidRootPart
    if not humanoid or not hrp then return false end
    
    -- Fliegenden Teppich ausrüsten
    local carpet = LP.Backpack:FindFirstChild("Flying Carpet")
    if carpet then
        humanoid:EquipTool(carpet)
    end
    
    -- Plot finden
    local plot = workspace.Plots:FindFirstChild(animalData.plot)
    if not plot then return false end
    
    -- Zielposition finden
    local targetPos = Vector3.new(0, 10, 0)
    
    local podiums = plot:FindFirstChild("AnimalPodiums")
    local animalFolder = podiums and podiums:FindFirstChild(animalData.slot)
    
    local allParts = {}
    local function scan(obj)
        for _, child in ipairs(obj:GetChildren()) do
            if child:IsA("BasePart") then
                table.insert(allParts, child)
            else
                scan(child)
            end
        end
    end
    
    if animalFolder then
        scan(animalFolder)
    end
    
    if #allParts > 0 then
        local closest, minDist = nil, math.huge
        local hrpPos = hrp.Position
        
        for _, part in ipairs(allParts) do
            local dist = (part.Position - hrpPos).Magnitude
            if dist < minDist then
                minDist = dist
                closest = part
            end
        end
        
        if closest then
            targetPos = closest.Position
        end
    else
        local spawnPart = plot:FindFirstChild("Spawn")
        if spawnPart and spawnPart:IsA("BasePart") then
            targetPos = Vector3.new(spawnPart.Position.X, targetPos.Y, spawnPart.Position.Z)
        else
            local plotPart = plot:FindFirstChildWhichIsA("BasePart")
            if plotPart then
                targetPos = Vector3.new(plotPart.Position.X, targetPos.Y, plotPart.Position.Z)
            end
        end
    end
    
    local animalY = targetPos.Y
    local highAnimal = animalY > 10
    local currentPos = hrp.Position
    
    -- SAFE TELEPORT (mit Teppich)
    if CONFIG.SAFE_TELEPORT then
        local carpetPart = workspace.Map:FindFirstChild("Carpet")
        if carpetPart and carpetPart:IsA("BasePart") then
            local carpetPos = getSmartCarpetPosition(carpetPart, currentPos)
            if carpetPos then
                local state = humanoid:GetState()
                if state ~= Enum.HumanoidStateType.Jumping and state ~= Enum.HumanoidStateType.Freefall then
                    humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                    task.wait(0.05)
                end
                
                hrp.Velocity = Vector3.new(hrp.Velocity.X, 200, hrp.Velocity.Z)
                task.wait(0.1)
                hrp.CFrame = CFrame.new(carpetPos.X, hrp.Position.Y, carpetPos.Z)
                task.wait(0.3)
                tpNearPlotIfFar(animalData)
                task.wait(0.3)
            end
        end
    else
        if highAnimal then
            local state = humanoid:GetState()
            if state ~= Enum.HumanoidStateType.Jumping and state ~= Enum.HumanoidStateType.Freefall then
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                task.wait(0.05)
            end
            hrp.Velocity = Vector3.new(hrp.Velocity.X, 200, hrp.Velocity.Z)
            task.wait(0.2)
        end
    end
    
    local finalPos = highAnimal and Vector3.new(targetPos.X, 20, targetPos.Z) or targetPos
    finalPos = getSafeOutsideDecorPos(plot, finalPos, currentPos)
    hrp.CFrame = CFrame.new(finalPos)
    
    return true
end

-- TELEPORT ZUM HÖCHSTEN ANIMAL
local function teleportToHighest()
    if #allAnimalsCache == 0 then return end
    
    if CONFIG.FAVORITES_PRIORITY and #FAVORITES > 0 then
        for _, favName in ipairs(FAVORITES) do
            for _, animal in ipairs(allAnimalsCache) do
                if animal.name:lower() == favName:lower() then
                    teleportToAnimal(animal)
                    return
                end
            end
        end
    end
    
    teleportToAnimal(allAnimalsCache[1])
end

-- ============================================================
-- ANIMAL SCANNER
-- ============================================================

local function isMyBaseAnimal(animalData)
    if not animalData or not animalData.plot then return false end
    
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return false end
    
    local plot = plots:FindFirstChild(animalData.plot)
    if not plot then return false end
    
    local channel = S.Synchronizer:Get(plot.Name)
    if channel then
        local owner = channel:Get("Owner")
        if owner then
            if typeof(owner) == "Instance" and owner:IsA("Player") then
                return owner.UserId == LP.UserId
            elseif typeof(owner) == "table" and owner.UserId then
                return owner.UserId == LP.UserId
            end
        end
    end
    
    local sign = plot:FindFirstChild("PlotSign")
    if sign then
        local yourBase = sign:FindFirstChild("YourBase")
        if yourBase and yourBase:IsA("BillboardGui") then
            return yourBase.Enabled == true
        end
    end
    
    return false
end

local function scanPlots()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return end
    
    local newCache = {}
    
    for _, plot in ipairs(plots:GetChildren()) do
        local channel = S.Synchronizer:Get(plot.Name)
        if channel then
            local animalList = channel:Get("AnimalList")
            local owner = channel:Get("Owner")
            
            if owner and animalList then
                for slot, animalData in pairs(animalList) do
                    if type(animalData) == "table" then
                        local animalName = animalData.Index
                        local animalInfo = S.AnimalsData[animalName]
                        if animalInfo then
                            local genValue = S.AnimalsShared:GetGeneration(animalName, animalData.Mutation, animalData.Traits, nil)
                            local genText = "$" .. S.NumberUtils:ToString(genValue) .. "/s"
                            
                            table.insert(newCache, {
                                name = animalInfo.DisplayName or animalName,
                                genText = genText,
                                genValue = genValue,
                                plot = plot.Name,
                                slot = tostring(slot),
                            })
                        end
                    end
                end
            end
        end
    end
    
    table.sort(newCache, function(a, b) return a.genValue > b.genValue end)
    allAnimalsCache = newCache
    return newCache
end

-- ============================================================
-- ANIMAL LIST (für PC)
-- ============================================================
local function refreshAnimalList()
    if not animalListFrame then return end
    
    for _, child in ipairs(animalListFrame:GetChildren()) do
        if child:IsA("Frame") and child.Name == "AnimalEntry" then
            child:Destroy()
        end
    end
    
    local displayCount = 0
    for _, animal in ipairs(allAnimalsCache) do
        if isMyBaseAnimal(animal) then continue end
        
        if searchQuery ~= "" then
            if not animal.name:lower():find(searchQuery:lower()) then
                continue
            end
        end
        
        local entry = Instance.new("Frame")
        entry.Name = "AnimalEntry"
        entry.Size = UDim2.new(1, -10, 0, 45)
        entry.BackgroundColor3 = COLORS.Surface
        entry.BackgroundTransparency = 0.4
        entry.LayoutOrder = displayCount
        entry.Parent = animalListFrame
        
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = entry
        
        local nameLabel = Instance.new("TextLabel")
        nameLabel.Size = UDim2.new(0.55, 0, 1, 0)
        nameLabel.Position = UDim2.new(0, 8, 0, 0)
        nameLabel.BackgroundTransparency = 1
        nameLabel.Text = animal.name
        nameLabel.TextColor3 = COLORS.Text
        nameLabel.Font = Enum.Font.GothamBold
        nameLabel.TextSize = 12
        nameLabel.TextXAlignment = Enum.TextXAlignment.Left
        nameLabel.Parent = entry
        
        local genLabel = Instance.new("TextLabel")
        genLabel.Size = UDim2.new(0.3, 0, 0.5, 0)
        genLabel.Position = UDim2.new(0.55, 0, 0.25, 0)
        genLabel.BackgroundTransparency = 1
        genLabel.Text = animal.genText
        genLabel.TextColor3 = COLORS.Cloud
        genLabel.Font = Enum.Font.GothamBold
        genLabel.TextSize = 10
        genLabel.Parent = entry
        
        local tpButton = Instance.new("TextButton")
        tpButton.Size = UDim2.new(0, 50, 0, 28)
        tpButton.Position = UDim2.new(1, -55, 0.5, -14)
        tpButton.BackgroundColor3 = COLORS.Cloud
        tpButton.BackgroundTransparency = 0.2
        tpButton.Text = "☁️"
        tpButton.TextColor3 = COLORS.Text
        tpButton.Font = Enum.Font.GothamBold
        tpButton.TextSize = 12
        tpButton.Parent = entry
        
        local btnCorner = Instance.new("UICorner")
        btnCorner.CornerRadius = UDim.new(0, 6)
        btnCorner.Parent = tpButton
        
        tpButton.MouseButton1Click:Connect(function()
            teleportToAnimal(animal)
        end)
        
        displayCount = displayCount + 1
    end
    
    local layout = animalListFrame:FindFirstChild("UIListLayout")
    if layout then
        animalListFrame.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
    end
end

-- ============================================================
-- UNIVERSAL GUI (Bottom-Right für beide)
-- ============================================================
local function createGUI()
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = "CloudHubTP"
    screenGui.ResetOnSpawn = false
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    screenGui.Parent = LP.PlayerGui
    
    -- Device-specific sizing
    local guiWidth, guiHeight, margin
    
    if isMobile then
        guiWidth = 200
        guiHeight = 280
        margin = 10
    else
        guiWidth = 320
        guiHeight = 460
        margin = 15
    end
    
    -- Main Frame (BOTTOM-RIGHT)
    mainFrame = Instance.new("Frame")
    mainFrame.Size = UDim2.new(0, guiWidth, 0, guiHeight)
    mainFrame.Position = UDim2.new(1, -guiWidth - margin, 1, -guiHeight - margin)
    mainFrame.BackgroundColor3 = COLORS.BG
    mainFrame.BackgroundTransparency = 0.1
    mainFrame.BorderSizePixel = 0
    mainFrame.Parent = screenGui
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 14)
    corner.Parent = mainFrame
    
    local stroke = Instance.new("UIStroke")
    stroke.Thickness = 1.5
    stroke.Color = COLORS.Cloud
    stroke.Transparency = 0.4
    stroke.Parent = mainFrame
    
    -- Header (draggable)
    local headerHeight = isMobile and 45 or 50
    local header = Instance.new("Frame")
    header.Size = UDim2.new(1, 0, 0, headerHeight)
    header.BackgroundTransparency = 1
    header.Parent = mainFrame
    
    -- Cloud Icon
    local iconSize = isMobile and 28 or 32
    local cloudIcon = Instance.new("TextLabel")
    cloudIcon.Size = UDim2.new(0, iconSize, 0, iconSize)
    cloudIcon.Position = UDim2.new(0, isMobile and 8 or 10, 0.5, -iconSize/2)
    cloudIcon.BackgroundTransparency = 1
    cloudIcon.Text = "☁️"
    cloudIcon.TextColor3 = COLORS.Cloud
    cloudIcon.Font = Enum.Font.GothamBold
    cloudIcon.TextSize = isMobile and 24 or 28
    cloudIcon.Parent = header
    
    -- Title
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -50, 0, isMobile and 20 or 24)
    title.Position = UDim2.new(0, isMobile and 40 or 45, 0, isMobile and 6 or 8)
    title.BackgroundTransparency = 1
    title.Text = "CLOUD HUB"
    title.TextColor3 = COLORS.CloudLight
    title.Font = Enum.Font.GothamBold
    title.TextSize = isMobile and 13 or 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = header
    
    -- Subtitle
    local subtitle = Instance.new("TextLabel")
    subtitle.Size = UDim2.new(1, -50, 0, 14)
    subtitle.Position = UDim2.new(0, isMobile and 40 or 45, 0, isMobile and 26 or 30)
    subtitle.BackgroundTransparency = 1
    subtitle.Text = "TP SYSTEM"
    subtitle.TextColor3 = COLORS.Dim
    subtitle.Font = Enum.Font.Gotham
    subtitle.TextSize = isMobile and 8 or 9
    subtitle.TextXAlignment = Enum.TextXAlignment.Left
    subtitle.Parent = header
    
    -- Minimize Button
    local minBtn = Instance.new("TextButton")
    minBtn.Size = UDim2.new(0, isMobile and 26 or 28, 0, isMobile and 26 or 28)
    minBtn.Position = UDim2.new(1, isMobile and -32 or -35, 0.5, isMobile and -13 or -14)
    minBtn.BackgroundColor3 = COLORS.Surface
    minBtn.BackgroundTransparency = 0.5
    minBtn.Text = "−"
    minBtn.TextColor3 = COLORS.Text
    minBtn.Font = Enum.Font.GothamBold
    minBtn.TextSize = isMobile and 16 or 18
    minBtn.Parent = header
    
    local minCorner = Instance.new("UICorner")
    minCorner.CornerRadius = UDim.new(1, 0)
    minCorner.Parent = minBtn
    
    -- Stats Section
    local statsY = headerHeight + (isMobile and 8 or 10)
    local statsHeight = isMobile and 65 or 70
    
    local statsFrame = Instance.new("Frame")
    statsFrame.Size = UDim2.new(1, -12, 0, statsHeight)
    statsFrame.Position = UDim2.new(0, 6, 0, statsY)
    statsFrame.BackgroundColor3 = COLORS.Surface
    statsFrame.BackgroundTransparency = 0.4
    statsFrame.Parent = mainFrame
    
    local statsCorner = Instance.new("UICorner")
    statsCorner.CornerRadius = UDim.new(0, 10)
    statsCorner.Parent = statsFrame
    
    -- Animal Count
    local countLabel = Instance.new("TextLabel")
    countLabel.Size = UDim2.new(0.5, 0, 0.6, 0)
    countLabel.Position = UDim2.new(0, 0, 0, isMobile and 4 or 6)
    countLabel.BackgroundTransparency = 1
    countLabel.Text = "0"
    countLabel.TextColor3 = COLORS.Text
    countLabel.Font = Enum.Font.GothamBold
    countLabel.TextSize = isMobile and 26 or 28
    countLabel.Parent = statsFrame
    
    local countSub = Instance.new("TextLabel")
    countSub.Size = UDim2.new(0.5, 0, 0.3, 0)
    countSub.Position = UDim2.new(0, 0, 0.65, 0)
    countSub.BackgroundTransparency = 1
    countSub.Text = "ANIMALS"
    countSub.TextColor3 = COLORS.Dim
    countSub.Font = Enum.Font.Gotham
    countSub.TextSize = isMobile and 8 or 9
    countSub.Parent = statsFrame
    
    -- Best Gen
    local bestLabel = Instance.new("TextLabel")
    bestLabel.Size = UDim2.new(0.5, 0, 0.6, 0)
    bestLabel.Position = UDim2.new(0.5, 0, 0, isMobile and 4 or 6)
    bestLabel.BackgroundTransparency = 1
    bestLabel.Text = "$0/s"
    bestLabel.TextColor3 = COLORS.Cloud
    bestLabel.Font = Enum.Font.GothamBold
    bestLabel.TextSize = isMobile and 14 or 16
    bestLabel.Parent = statsFrame
    
    local bestSub = Instance.new("TextLabel")
    bestSub.Size = UDim2.new(0.5, 0, 0.3, 0)
    bestSub.Position = UDim2.new(0.5, 0, 0.65, 0)
    bestSub.BackgroundTransparency = 1
    bestSub.Text = "HIGHEST"
    bestSub.TextColor3 = COLORS.Dim
    bestSub.Font = Enum.Font.Gotham
    bestSub.TextSize = isMobile and 8 or 9
    bestSub.Parent = statsFrame
    
    -- TP Button
    local tpY = statsY + statsHeight + (isMobile and 8 or 10)
    local tpHeight = isMobile and 45 or 48
    
    local tpBtn = Instance.new("TextButton")
    tpBtn.Size = UDim2.new(1, -12, 0, tpHeight)
    tpBtn.Position = UDim2.new(0, 6, 0, tpY)
    tpBtn.BackgroundColor3 = COLORS.Cloud
    tpBtn.BackgroundTransparency = 0.2
    tpBtn.Text = isMobile and "☁️ TP" or "☁️ TP HIGHEST"
    tpBtn.TextColor3 = COLORS.Text
    tpBtn.Font = Enum.Font.GothamBold
    tpBtn.TextSize = isMobile and 13 or 14
    tpBtn.Parent = mainFrame
    
    local tpCorner = Instance.new("UICorner")
    tpCorner.CornerRadius = UDim.new(0, 10)
    tpCorner.Parent = tpBtn
    
    -- PC ONLY: Search Box and Animal List
    if not isMobile then
        local searchY = tpY + tpHeight + 8
        searchBox = Instance.new("TextBox")
        searchBox.Size = UDim2.new(1, -12, 0, 32)
        searchBox.Position = UDim2.new(0, 6, 0, searchY)
        searchBox.BackgroundColor3 = COLORS.Surface
        searchBox.BackgroundTransparency = 0.4
        searchBox.PlaceholderText = "🔍 Search..."
        searchBox.TextColor3 = COLORS.Text
        searchBox.PlaceholderColor3 = COLORS.Dim
        searchBox.Font = Enum.Font.Gotham
        searchBox.TextSize = 12
        searchBox.Parent = mainFrame
        
        local searchCorner = Instance.new("UICorner")
        searchCorner.CornerRadius = UDim.new(0, 8)
        searchCorner.Parent = searchBox
        
        searchBox:GetPropertyChangedSignal("Text"):Connect(function()
            searchQuery = searchBox.Text
            refreshAnimalList()
        end)
        
        local listY = searchY + 38
        local listHeight = guiHeight - listY - 52
        
        animalListFrame = Instance.new("ScrollingFrame")
        animalListFrame.Size = UDim2.new(1, -12, 0, listHeight)
        animalListFrame.Position = UDim2.new(0, 6, 0, listY)
        animalListFrame.BackgroundColor3 = COLORS.BG
        animalListFrame.BackgroundTransparency = 0.9
        animalListFrame.BorderSizePixel = 0
        animalListFrame.ScrollBarThickness = 3
        animalListFrame.ScrollBarImageColor3 = COLORS.Cloud
        animalListFrame.Parent = mainFrame
        
        local listCorner = Instance.new("UICorner")
        listCorner.CornerRadius = UDim.new(0, 8)
        listCorner.Parent = animalListFrame
        
        local listLayout = Instance.new("UIListLayout")
        listLayout.Padding = UDim.new(0, 5)
        listLayout.SortOrder = Enum.SortOrder.LayoutOrder
        listLayout.Parent = animalListFrame
        
        listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            animalListFrame.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 10)
        end)
    end
    
    -- Button Row
    local btnRowY = isMobile and (tpY + tpHeight + 8) or (guiHeight - 48)
    local btnRowHeight = isMobile and 36 or 38
    
    local buttonRow = Instance.new("Frame")
    buttonRow.Size = UDim2.new(1, -12, 0, btnRowHeight)
    buttonRow.Position = UDim2.new(0, 6, 0, btnRowY)
    buttonRow.BackgroundTransparency = 1
    buttonRow.Parent = mainFrame
    
    -- Refresh Button
    local refreshBtn = Instance.new("TextButton")
    refreshBtn.Size = UDim2.new(0.48, 0, 1, 0)
    refreshBtn.Position = UDim2.new(0, 0, 0, 0)
    refreshBtn.BackgroundColor3 = COLORS.Surface
    refreshBtn.BackgroundTransparency = 0.5
    refreshBtn.Text = "🔄"
    refreshBtn.TextColor3 = COLORS.Text
    refreshBtn.Font = Enum.Font.GothamBold
    refreshBtn.TextSize = isMobile and 12 or 13
    refreshBtn.Parent = buttonRow
    
    local refreshCorner = Instance.new("UICorner")
    refreshCorner.CornerRadius = UDim.new(0, 8)
    refreshCorner.Parent = refreshBtn
    
    -- Settings Button
    local settingsBtn = Instance.new("TextButton")
    settingsBtn.Size = UDim2.new(0.48, 0, 1, 0)
    settingsBtn.Position = UDim2.new(0.52, 0, 0, 0)
    settingsBtn.BackgroundColor3 = COLORS.Surface
    settingsBtn.BackgroundTransparency = 0.5
    settingsBtn.Text = "⚙️"
    settingsBtn.TextColor3 = COLORS.Text
    settingsBtn.Font = Enum.Font.GothamBold
    settingsBtn.TextSize = isMobile and 12 or 13
    settingsBtn.Parent = buttonRow
    
    local settingsCorner = Instance.new("UICorner")
    settingsCorner.CornerRadius = UDim.new(0, 8)
    settingsCorner.Parent = settingsBtn
    
    -- Settings Panel
    local settingsPanel = Instance.new("Frame")
    settingsPanel.Size = UDim2.new(1, -12, 0, 80)
    settingsPanel.Position = UDim2.new(0, 6, 1, -92)
    settingsPanel.BackgroundColor3 = COLORS.Surface
    settingsPanel.BackgroundTransparency = 0.7
    settingsPanel.Visible = false
    settingsPanel.Parent = mainFrame
    
    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 10)
    panelCorner.Parent = settingsPanel
    
    -- Safe Teleport Toggle
    local safeToggle = Instance.new("TextButton")
    safeToggle.Size = UDim2.new(1, -12, 0, 32)
    safeToggle.Position = UDim2.new(0, 6, 0, 6)
    safeToggle.BackgroundColor3 = COLORS.BG
    safeToggle.BackgroundTransparency = 0.6
    safeToggle.Text = CONFIG.SAFE_TELEPORT and "✅ Safe TP" or "❌ Safe TP"
    safeToggle.TextColor3 = CONFIG.SAFE_TELEPORT and COLORS.Green or COLORS.Red
    safeToggle.Font = Enum.Font.Gotham
    safeToggle.TextSize = isMobile and 10 or 11
    safeToggle.Parent = settingsPanel
    
    local safeCorner = Instance.new("UICorner")
    safeCorner.CornerRadius = UDim.new(0, 6)
    safeCorner.Parent = safeToggle
    
    -- Priority Toggle
    local priorityToggle = Instance.new("TextButton")
    priorityToggle.Size = UDim2.new(1, -12, 0, 32)
    priorityToggle.Position = UDim2.new(0, 6, 0, 42)
    priorityToggle.BackgroundColor3 = COLORS.BG
    priorityToggle.BackgroundTransparency = 0.6
    priorityToggle.Text = CONFIG.FAVORITES_PRIORITY and "⭐ Priority" or "⭐ Priority OFF"
    priorityToggle.TextColor3 = CONFIG.FAVORITES_PRIORITY and COLORS.Yellow or COLORS.Dim
    priorityToggle.Font = Enum.Font.Gotham
    priorityToggle.TextSize = isMobile and 10 or 11
    priorityToggle.Parent = settingsPanel
    
    local priorityCorner = Instance.new("UICorner")
    priorityCorner.CornerRadius = UDim.new(0, 6)
    priorityCorner.Parent = priorityToggle
    
    -- ============================================================
    -- BUTTON ACTIONS
    -- ============================================================
    local settingsVisible = false
    
    tpBtn.MouseButton1Click:Connect(teleportToHighest)
    
    refreshBtn.MouseButton1Click:Connect(function()
        scanPlots()
        local total = #allAnimalsCache
        countLabel.Text = tostring(total)
        if total > 0 then
            bestLabel.Text = allAnimalsCache[1].genText
        end
        if not isMobile and animalListFrame then
            refreshAnimalList()
        end
        TweenService:Create(refreshBtn, TweenInfo.new(0.2), {BackgroundTransparency = 0.3}):Play()
        task.wait(0.1)
        TweenService:Create(refreshBtn, TweenInfo.new(0.2), {BackgroundTransparency = 0.5}):Play()
    end)
    
    settingsBtn.MouseButton1Click:Connect(function()
        settingsVisible = not settingsVisible
        settingsPanel.Visible = settingsVisible
    end)
    
    safeToggle.MouseButton1Click:Connect(function()
        CONFIG.SAFE_TELEPORT = not CONFIG.SAFE_TELEPORT
        safeToggle.Text = CONFIG.SAFE_TELEPORT and "✅ Safe TP" or "❌ Safe TP"
        safeToggle.TextColor3 = CONFIG.SAFE_TELEPORT and COLORS.Green or COLORS.Red
    end)
    
    priorityToggle.MouseButton1Click:Connect(function()
        CONFIG.FAVORITES_PRIORITY = not CONFIG.FAVORITES_PRIORITY
        priorityToggle.Text = CONFIG.FAVORITES_PRIORITY and "⭐ Priority" or "⭐ Priority OFF"
        priorityToggle.TextColor3 = CONFIG.FAVORITES_PRIORITY and COLORS.Yellow or COLORS.Dim
    end)
    
    -- Minimize function
    local content = {statsFrame, tpBtn, buttonRow, settingsPanel}
    if not isMobile then
        table.insert(content, searchBox)
        table.insert(content, animalListFrame)
    end
    
    minBtn.MouseButton1Click:Connect(function()
        minimized = not minimized
        minBtn.Text = minimized and "+" or "−"
        for _, obj in ipairs(content) do
            if obj then obj.Visible = not minimized end
        end
        mainFrame.Size = minimized and UDim2.new(0, guiWidth, 0, headerHeight + 5) or UDim2.new(0, guiWidth, 0, guiHeight)
    end)
    
    -- Dragging (Touch & Mouse)
    local dragging, dragStart, startPos = false
    
    header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
            dragging = true
            dragStart = input.Position
            startPos = mainFrame.Position
        end
    end)
    
    header.InputEnded:Connect(function()
        dragging = false
    end)
    
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
            local delta = input.Position - dragStart
            mainFrame.Position = UDim2.new(
                startPos.X.Scale,
                startPos.X.Offset + delta.X,
                startPos.Y.Scale,
                startPos.Y.Offset + delta.Y
            )
        end
    end)
    
    return {countLabel, bestLabel}
end

-- ============================================================
-- FAVORITES MANAGEMENT
-- ============================================================
local function saveFavorites()
    local success, json = pcall(game:GetService("HttpService").JSONEncode, game:GetService("HttpService"), FAVORITES)
    if success then
        writefile("CloudHubFavorites.json", json)
    end
end

local function loadFavorites()
    if not isfile("CloudHubFavorites.json") then return end
    local success, json = pcall(readfile, "CloudHubFavorites.json")
    if not success then return end
    local success2, data = pcall(game:GetService("HttpService").JSONDecode, game:GetService("HttpService"), json)
    if success2 and data then
        for _, name in ipairs(data) do
            table.insert(FAVORITES, name)
        end
    end
end

-- ============================================================
-- INIT
-- ============================================================
local function init()
    loadFavorites()
    getgenv().CLOUD_FAVORITES = FAVORITES
    
    local labels = createGUI()
    local countLabel, bestLabel = labels[1], labels[2]
    
    -- Initial scan
    task.spawn(function()
        task.wait(1)
        local animals = scanPlots()
        if animals then
            countLabel.Text = tostring(#animals)
            if #animals > 0 then
                bestLabel.Text = animals[1].genText
            end
        end
        if not isMobile and animalListFrame then
            refreshAnimalList()
        end
    end)
    
    -- Auto-refresh loop
    task.spawn(function()
        while true do
            task.wait(CONFIG.REFRESH_INTERVAL)
            local animals = scanPlots()
            if animals then
                countLabel.Text = tostring(#animals)
                if #animals > 0 then
                    bestLabel.Text = animals[1].genText
                end
                if not isMobile and animalListFrame then
                    refreshAnimalList()
                end
            end
        end
    end)
    
    print("========================================")
    print("☁️ CLOUD HUB TP - UNIVERSAL EDITION")
    print("   Device: " .. deviceType)
    print("   Teleport System: PREMIUM (Brainrot)")
    print("   Safe Teleport: " .. (CONFIG.SAFE_TELEPORT and "ON" or "OFF"))
    print("   Priority Mode: " .. (CONFIG.FAVORITES_PRIORITY and "ON" or "OFF"))
    print("========================================")
end

init()
