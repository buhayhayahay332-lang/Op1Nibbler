-- player esp, drone esp, claymore esp (BOX)
-- OPTIMIZED VERSION (Single Render Loop)

local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

local camera = workspace.CurrentCamera

local ESP_ENABLED = true
local TEAM_CHECK  = true        

local PLAYER_BOX_ENABLED = true
local PLAYER_BOX_COLOR   = Color3.fromRGB(210,  50,  80)
local PLAYER_BOX_THICK   = 2
local PLAYER_BOX_TRANSP  = 1

local OBJECT_BOX_ENABLED = true
local DRONE_BOX_COLOR           = Color3.fromRGB(0,   255, 255)  
local CLAYMORE_BOX_COLOR        = Color3.fromRGB(255,   0,   0)
local PROXIMITY_ALARM_BOX_COLOR = Color3.fromRGB(255, 165,   0)
local STICKY_CAMERA_BOX_COLOR   = Color3.fromRGB(255, 192, 203)
local OBJECT_BOX_THICK   = 1.5
local OBJECT_BOX_TRANSP  = 0.9

local teamCache      = {}
local lastCache      = 0
local CACHE_INTERVAL = 0.7

-- Pre-allocated arrays to reduce garbage
local corners = {}
for i = 1, 8 do corners[i] = Vector3.new(0, 0, 0) end
local points = {}
for i = 1, 8 do points[i] = Vector3.new(0, 0, 0) end

local function updateTeamCache()
    teamCache = {}
    for _, v in ipairs(Workspace:GetChildren()) do
        if v:IsA("Highlight") and v.Adornee then
            teamCache[v.Adornee] = true
        end
    end
    lastCache = tick()
end

local function isOnScreen(worldPos)
    local screenPos, onScreen = camera:WorldToViewportPoint(worldPos)
    return onScreen
end

local function isInFrustum(worldPos)
    -- Check if object is within camera frustum
    local relativePos = worldPos - camera.CFrame.Position
    local lookDir = camera.CFrame.LookVector
    
    -- Object must be in front of camera (dot product > 0)
    if relativePos:Dot(lookDir) <= 0 then
        return false
    end
    
    -- Check if within viewing angle (rough frustum check)
    -- FOV is typically 70 degrees, so we check against a reasonable angle
    local angle = math.acos(math.min(1, relativePos.Unit:Dot(lookDir)))
    return angle < math.rad(60)  -- 60 degree half-angle
end

local function isTeammate(model)
    if not TEAM_CHECK then return false end
    local t = tick()
    if t - lastCache > CACHE_INTERVAL then
        updateTeamCache()
    end
    return teamCache[model] == true
end

-- OBJECT BOX (PRECISE)
local function getPrecise2DBox(model, cachedBox)
    local cf, size = model:GetBoundingBox()
    
    -- Early exit: frustum culling (is it in camera view?)
    if not isInFrustum(cf.Position) then
        return nil
    end
    
    -- Early exit: quick viewport bounds check on center
    if not isOnScreen(cf.Position) then
        return nil
    end
    
    local halfX, halfY, halfZ = size.X/2, size.Y/2, size.Z/2
    
    corners[1] = cf * Vector3.new(-halfX, -halfY, -halfZ)
    corners[2] = cf * Vector3.new(-halfX, -halfY,  halfZ)
    corners[3] = cf * Vector3.new(-halfX,  halfY, -halfZ)
    corners[4] = cf * Vector3.new(-halfX,  halfY,  halfZ)
    corners[5] = cf * Vector3.new( halfX, -halfY, -halfZ)
    corners[6] = cf * Vector3.new( halfX, -halfY,  halfZ)
    corners[7] = cf * Vector3.new( halfX,  halfY, -halfZ)
    corners[8] = cf * Vector3.new( halfX,  halfY,  halfZ)

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyVisible = false

    for i = 1, 8 do
        local corner = corners[i]
        local screenPos, onScreen = camera:WorldToViewportPoint(corner)
        if onScreen then
            anyVisible = true
            minX = math.min(minX, screenPos.X)
            minY = math.min(minY, screenPos.Y)
            maxX = math.max(maxX, screenPos.X)
            maxY = math.max(maxY, screenPos.Y)
        end
    end

    if not anyVisible then return nil end

    return {
        position = Vector2.new(minX, minY),
        size     = Vector2.new(maxX - minX, maxY - minY)
    }
end

-- PLAYER BOX
local function getPlayerBox(model, cachedComponents)
    local head = cachedComponents.head
    local torso = cachedComponents.torso

    if not head or not torso or not cachedComponents.isVisible then 
        return nil 
    end
    -- Early exit: frustum culling (is it in camera view?)
    if not isInFrustum(torso.Position) then
        return nil
    end
    -- Early exit: quick viewport bounds check on torso center
    if not isOnScreen(torso.Position) then
        return nil
    end

    -- Simplified: use only 4 key points instead of 8
    local hsx, hsy = head.Size.X/2, head.Size.Y/2
    local tsx, tsy = torso.Size.X/2, torso.Size.Y/2
    
    points[1] = head.Position + Vector3.new(-hsx, hsy, 0)   -- head top-left
    points[2] = head.Position + Vector3.new( hsx, hsy, 0)   -- head top-right
    points[3] = torso.Position + Vector3.new(-tsx, -tsy, 0) -- torso bottom-left
    points[4] = torso.Position + Vector3.new( tsx, -tsy, 0) -- torso bottom-right

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local anyVisible = false

    for i = 1, 4 do
        local screenPos, onScreen = camera:WorldToViewportPoint(points[i])
        if onScreen then
            anyVisible = true
            minX = math.min(minX, screenPos.X)
            minY = math.min(minY, screenPos.Y)
            maxX = math.max(maxX, screenPos.X)
            maxY = math.max(maxY, screenPos.Y)
        end
    end

    if not anyVisible then return nil end

    local padding = 3

    return {
        position = Vector2.new(minX - padding, minY - padding),
        size     = Vector2.new((maxX - minX) + padding * 2, (maxY - minY) + padding * 2)
    }
end

local playerBoxes = {}
local objectBoxes = {}

-- CREATE PLAYER BOX (stores metadata, not connections)
local function createPlayerBox(char)
    if playerBoxes[char] then return end
    if char.Name == "LocalViewmodel" then return end

    local head = char:FindFirstChild("head")
    local torso = char:FindFirstChild("torso")
    
    if not head or not torso then return end

    local box = Drawing.new("Square")
    box.Visible      = false
    box.Filled       = false
    box.Thickness    = PLAYER_BOX_THICK
    box.Transparency = PLAYER_BOX_TRANSP
    box.Color        = PLAYER_BOX_COLOR
    box.ZIndex       = 2

    -- Initial visibility state
    local isVisible =  torso.Transparency <= 0.95

    playerBoxes[char] = {
        box = box,
        components = {
            head = head,
            torso = torso,
            leftArm = char:FindFirstChild("arm1"),
            rightArm = char:FindFirstChild("arm2"),
            isVisible = isVisible
        },
        lastPos = Vector3.new(0, 0, 0),
        renderConn = nil,
        ancestryConn = nil
    }

    -- Event-based transparency listeners (only fires when transparency actually changes)
    local headTransConn = head:GetPropertyChangedSignal("Transparency"):Connect(function()
        local data = playerBoxes[char]
        if data then
            data.components.isVisible = ( torso.Transparency <= 0.95)
        end
    end)

    local torsoTransConn = torso:GetPropertyChangedSignal("Transparency"):Connect(function()
        local data = playerBoxes[char]
        if data then
            data.components.isVisible = ( torso.Transparency <= 0.95)
        end
    end)

    -- Only set up ancestry cleanup, not a render loop
    local ancestryConn
    ancestryConn = char.AncestryChanged:Connect(function(_, parent)
        if not parent then
            local data = playerBoxes[char]
            if data then
                headTransConn:Disconnect()
                torsoTransConn:Disconnect()
                data.box:Remove()
                if data.renderConn then data.renderConn:Disconnect() end
                if data.ancestryConn then data.ancestryConn:Disconnect() end
                playerBoxes[char] = nil
            end
        end
    end)
    playerBoxes[char].ancestryConn = ancestryConn
end

-- CREATE OBJECT BOX
local function createObjectBox(obj)
    if objectBoxes[obj] then return end

    local box = Drawing.new("Square")
    box.Visible      = false
    box.Filled       = false
    box.Thickness    = OBJECT_BOX_THICK
    box.Transparency = OBJECT_BOX_TRANSP
    box.ZIndex       = 3

    objectBoxes[obj] = {
        box = box,
        lastPos = Vector3.new(0, 0, 0),
        ancestryConn = nil
    }

    -- Set color based on object type
    if obj.Name == "Drone" then
        box.Color = DRONE_BOX_COLOR
    elseif obj.Name == "Claymore" then
        box.Color = CLAYMORE_BOX_COLOR
    elseif obj.Name == "ProximityAlarm" then
        box.Color = PROXIMITY_ALARM_BOX_COLOR
    elseif obj.Name == "StickyCamera" then
        box.Color = STICKY_CAMERA_BOX_COLOR
    else
        box:Remove()
        objectBoxes[obj] = nil
        return
    end

    -- Only set up ancestry cleanup
    local ancestryConn
    ancestryConn = obj.AncestryChanged:Connect(function(_, parent)
        if not parent then
            local data = objectBoxes[obj]
            if data then
                data.box:Remove()
                if data.ancestryConn then data.ancestryConn:Disconnect() end
                objectBoxes[obj] = nil
            end
        end
    end)
    objectBoxes[obj].ancestryConn = ancestryConn
end

-- INITIAL SCAN
local function initialScan()
    local vmFolder = Workspace:WaitForChild("Viewmodels", 10)
    if not vmFolder then
        warn("Viewmodels folder not found")
        return
    end

    for _, model in ipairs(vmFolder:GetChildren()) do
        if model:IsA("Model") and model.Name ~= "LocalViewmodel" then
            task.spawn(createPlayerBox, model)
        end
    end

    vmFolder.ChildAdded:Connect(function(model)
        if model:IsA("Model") and model.Name ~= "LocalViewmodel" then
            task.delay(0.25, function()
                createPlayerBox(model)
            end)
        end
    end)

    for _, child in ipairs(Workspace:GetChildren()) do
        if child.Name == "Drone" or child.Name == "Claymore" or child.Name == "ProximityAlarm" or child.Name == "StickyCamera" then
            task.spawn(createObjectBox, child)
        end
    end
end

Workspace.ChildAdded:Connect(function(child)
    if child.Name == "Drone" or child.Name == "Claymore" or child.Name == "ProximityAlarm" or child.Name == "StickyCamera" then
        task.spawn(createObjectBox, child)
    end
end)

-- SINGLE RENDER LOOP (OPTIMIZED)
local mainRenderConn
mainRenderConn = RunService.RenderStepped:Connect(function()
    if not ESP_ENABLED then
        for _, data in pairs(playerBoxes) do
            data.box.Visible = false
        end
        for _, data in pairs(objectBoxes) do
            data.box.Visible = false
        end
        return
    end

    -- Update team cache
    local t = tick()
    if t - lastCache > CACHE_INTERVAL then
        updateTeamCache()
    end

    -- UPDATE PLAYER BOXES
    if PLAYER_BOX_ENABLED then
        for char, data in pairs(playerBoxes) do
            if char:IsDescendantOf(Workspace) then
                if isTeammate(char) then
                    data.box.Visible = false
                else
                    local boxData = getPlayerBox(char, data.components)
                    if boxData then
                        data.box.Position = boxData.position
                        data.box.Size     = boxData.size
                        data.box.Visible  = true
                    else
                        data.box.Visible = false
                    end
                end
            else
                -- Clean up dead players
                data.box:Remove()
                if data.ancestryConn then data.ancestryConn:Disconnect() end
                playerBoxes[char] = nil
            end
        end
    else
        for char, data in pairs(playerBoxes) do
            data.box.Visible = false
        end
    end

    -- UPDATE OBJECT BOXES
    if OBJECT_BOX_ENABLED then
        for obj, data in pairs(objectBoxes) do
            if obj:IsDescendantOf(Workspace) then
                local boxData = getPrecise2DBox(obj)
                if boxData then
                    data.box.Position = boxData.position
                    data.box.Size     = boxData.size
                    data.box.Visible  = true
                else
                    data.box.Visible = false
                end
            else
                -- Clean up destroyed objects
                data.box:Remove()
                if data.ancestryConn then data.ancestryConn:Disconnect() end
                objectBoxes[obj] = nil
            end
        end
    else
        for obj, data in pairs(objectBoxes) do
            data.box.Visible = false
        end
    end
end)

task.spawn(initialScan)

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.Insert then
        ESP_ENABLED = not ESP_ENABLED
        print("ESP " .. (ESP_ENABLED and "ON" or "OFF"))
    end
end)
