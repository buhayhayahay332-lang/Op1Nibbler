return function(ctx)
    local Runtime = ctx and ctx.Runtime or {}
    local cloneref = Runtime.cloneref or cloneref or function(v)
        return v
    end
    local clonefunction = Runtime.clonefunction or clonefunction or function(v)
        return v
    end
    local Services = ctx and ctx.Services or {}

    local Workspace = Services.Workspace or cloneref(game:GetService("Workspace"))
    local RunService = Services.RunService or cloneref(game:GetService("RunService"))
    local UserInputService = Services.UserInputService or cloneref(game:GetService("UserInputService"))

    local tickFn = tick
    local acos = math.acos
    local min = math.min
    local max = math.max
    local rad = math.rad
    local huge = math.huge
    local Vector2new = Vector2.new
    local Vector3new = Vector3.new

    local ESP_ENABLED = false
    local TEAM_CHECK = true

    local PLAYER_BOX_ENABLED = true
    local PLAYER_BOX_COLOR = Color3.fromRGB(210, 50, 80)
    local PLAYER_BOX_THICK = 2
    local PLAYER_BOX_TRANSP = 1

    local OBJECT_BOX_ENABLED = true
    local DRONE_BOX_COLOR = Color3.fromRGB(0, 255, 255)
    local CLAYMORE_BOX_COLOR = Color3.fromRGB(255, 0, 0)
    local PROXIMITY_ALARM_BOX_COLOR = Color3.fromRGB(255, 165, 0)
    local STICKY_CAMERA_BOX_COLOR = Color3.fromRGB(255, 192, 203)
    local OBJECT_BOX_THICK = 1.5
    local OBJECT_BOX_TRANSP = 0.9

    local TEAM_CACHE = {}
    local LAST_TEAM_CACHE = 0
    local TEAM_CACHE_INTERVAL = 0.7

    local playerBoxes = {}
    local objectBoxes = {}
    local connections = {}
    local mainRenderConn = nil

    local OBJECT_WHITELIST = {
        Drone = true,
        Claymore = true,
        ProximityAlarm = true,
        StickyCamera = true
    }

    local corners = {}
    local points = {}
    for i = 1, 8 do
        corners[i] = Vector3new(0, 0, 0)
    end
    for i = 1, 4 do
        points[i] = Vector3new(0, 0, 0)
    end

    local currentCamera = Workspace.CurrentCamera
    local worldToViewportPoint = currentCamera and clonefunction(currentCamera.WorldToViewportPoint) or nil

    local M = {
        initialized = false,
        enabled = ESP_ENABLED,
        teamCheck = TEAM_CHECK,
        playerBoxEnabled = PLAYER_BOX_ENABLED,
        objectBoxEnabled = OBJECT_BOX_ENABLED,
        playerColor = PLAYER_BOX_COLOR,
        droneColor = DRONE_BOX_COLOR,
        claymoreColor = CLAYMORE_BOX_COLOR,
        proximityColor = PROXIMITY_ALARM_BOX_COLOR,
        stickyColor = STICKY_CAMERA_BOX_COLOR,
        playerThickness = PLAYER_BOX_THICK,
        objectThickness = OBJECT_BOX_THICK
    }

    local function clearMap(map)
        for k in next, map do
            map[k] = nil
        end
    end

    local function updateCamera()
        currentCamera = Workspace.CurrentCamera
        worldToViewportPoint = currentCamera and clonefunction(currentCamera.WorldToViewportPoint) or nil
    end

    local function worldToScreen(worldPos)
        if not currentCamera or not worldToViewportPoint then
            return nil, false
        end
        return worldToViewportPoint(currentCamera, worldPos)
    end

    local function updateTeamCache()
        clearMap(TEAM_CACHE)
        local children = Workspace:GetChildren()
        for i = 1, #children do
            local obj = children[i]
            if obj:IsA("Highlight") and obj.Adornee then
                TEAM_CACHE[obj.Adornee] = true
            end
        end
        LAST_TEAM_CACHE = tickFn()
    end

    local function isTeammate(model)
        if not TEAM_CHECK then
            return false
        end
        if tickFn() - LAST_TEAM_CACHE > TEAM_CACHE_INTERVAL then
            updateTeamCache()
        end
        return TEAM_CACHE[model] == true
    end

    local function isInFrustum(worldPos)
        if not currentCamera then
            return false
        end

        local relativePos = worldPos - currentCamera.CFrame.Position
        local lookDir = currentCamera.CFrame.LookVector
        if relativePos:Dot(lookDir) <= 0 then
            return false
        end

        local mag = relativePos.Magnitude
        if mag <= 0 then
            return true
        end

        local angle = acos(min(1, relativePos.Unit:Dot(lookDir)))
        return angle < rad(60)
    end

    local function isOnScreen(worldPos)
        local _, onScreen = worldToScreen(worldPos)
        return onScreen
    end

    local function createBox(color, thickness, transparency, zIndex)
        local box = Drawing.new("Square")
        box.Visible = false
        box.Filled = false
        box.Thickness = thickness
        box.Transparency = transparency
        box.Color = color
        box.ZIndex = zIndex
        return box
    end

    local function getObjectColor(name)
        if name == "Drone" then
            return DRONE_BOX_COLOR
        elseif name == "Claymore" then
            return CLAYMORE_BOX_COLOR
        elseif name == "ProximityAlarm" then
            return PROXIMITY_ALARM_BOX_COLOR
        elseif name == "StickyCamera" then
            return STICKY_CAMERA_BOX_COLOR
        end
        return nil
    end

    local function resolvePlayerParts(char)
        local head = char:FindFirstChild("head") or char:FindFirstChild("Head")
        local torso = char:FindFirstChild("torso") or char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso") or
            char:FindFirstChild("HumanoidRootPart")

        if not head or not torso then
            return nil, nil
        end
        if not head:IsA("BasePart") or not torso:IsA("BasePart") then
            return nil, nil
        end

        return head, torso
    end

    local function getObjectBox2D(model)
        local cf, size = model:GetBoundingBox()

        if not isInFrustum(cf.Position) or not isOnScreen(cf.Position) then
            return false
        end

        local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
        corners[1] = cf * Vector3new(-hx, -hy, -hz)
        corners[2] = cf * Vector3new(-hx, -hy, hz)
        corners[3] = cf * Vector3new(-hx, hy, -hz)
        corners[4] = cf * Vector3new(-hx, hy, hz)
        corners[5] = cf * Vector3new(hx, -hy, -hz)
        corners[6] = cf * Vector3new(hx, -hy, hz)
        corners[7] = cf * Vector3new(hx, hy, -hz)
        corners[8] = cf * Vector3new(hx, hy, hz)

        local minX, minY = huge, huge
        local maxX, maxY = -huge, -huge
        local anyVisible = false

        for i = 1, 8 do
            local screenPos, visible = worldToScreen(corners[i])
            if visible then
                anyVisible = true
                local x, y = screenPos.X, screenPos.Y
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            end
        end

        if not anyVisible then
            return false
        end

        return true, minX, minY, maxX - minX, maxY - minY
    end

    local function getPlayerBox2D(head, torso)
        if not head or not torso then
            return false
        end

        local torsoPos = torso.Position
        if not isInFrustum(torsoPos) or not isOnScreen(torsoPos) then
            return false
        end

        local hsx, hsy = head.Size.X * 0.5, head.Size.Y * 0.5
        local tsx, tsy = torso.Size.X * 0.5, torso.Size.Y * 0.5

        points[1] = head.Position + Vector3new(-hsx, hsy, 0)
        points[2] = head.Position + Vector3new(hsx, hsy, 0)
        points[3] = torso.Position + Vector3new(-tsx, -tsy, 0)
        points[4] = torso.Position + Vector3new(tsx, -tsy, 0)

        local minX, minY = huge, huge
        local maxX, maxY = -huge, -huge
        local anyVisible = false

        for i = 1, 4 do
            local screenPos, visible = worldToScreen(points[i])
            if visible then
                anyVisible = true
                local x, y = screenPos.X, screenPos.Y
                minX = min(minX, x)
                minY = min(minY, y)
                maxX = max(maxX, x)
                maxY = max(maxY, y)
            end
        end

        if not anyVisible then
            return false
        end

        local padding = 3
        return true, minX - padding, minY - padding, (maxX - minX) + padding * 2, (maxY - minY) + padding * 2
    end

    local function cleanupPlayerBox(char)
        local data = playerBoxes[char]
        if not data then
            return
        end

        if data.headConn then data.headConn:Disconnect() end
        if data.torsoConn then data.torsoConn:Disconnect() end
        if data.ancestryConn then data.ancestryConn:Disconnect() end
        if data.box then data.box:Remove() end

        playerBoxes[char] = nil
    end

    local function cleanupObjectBox(obj)
        local data = objectBoxes[obj]
        if not data then
            return
        end

        if data.ancestryConn then data.ancestryConn:Disconnect() end
        if data.box then data.box:Remove() end

        objectBoxes[obj] = nil
    end

    local function createPlayerBox(char)
        if playerBoxes[char] or char.Name == "LocalViewmodel" then
            return
        end

        local head, torso = resolvePlayerParts(char)
        if not head or not torso then
            return
        end

        local data = {
            box = createBox(PLAYER_BOX_COLOR, PLAYER_BOX_THICK, PLAYER_BOX_TRANSP, 2),
            head = head,
            torso = torso,
            isVisible = torso.Transparency <= 0.95,
            headConn = nil,
            torsoConn = nil,
            ancestryConn = nil
        }

        data.headConn = head:GetPropertyChangedSignal("Transparency"):Connect(function()
            local cached = playerBoxes[char]
            if cached and cached.torso then
                cached.isVisible = cached.torso.Transparency <= 0.95
            end
        end)

        data.torsoConn = torso:GetPropertyChangedSignal("Transparency"):Connect(function()
            local cached = playerBoxes[char]
            if cached and cached.torso then
                cached.isVisible = cached.torso.Transparency <= 0.95
            end
        end)

        data.ancestryConn = char.AncestryChanged:Connect(function(_, parent)
            if not parent then
                cleanupPlayerBox(char)
            end
        end)

        playerBoxes[char] = data
    end

    local function createObjectBox(obj)
        if objectBoxes[obj] or not OBJECT_WHITELIST[obj.Name] then
            return
        end

        local color = getObjectColor(obj.Name)
        if not color then
            return
        end

        objectBoxes[obj] = {
            box = createBox(color, OBJECT_BOX_THICK, OBJECT_BOX_TRANSP, 3),
            ancestryConn = obj.AncestryChanged:Connect(function(_, parent)
                if not parent then
                    cleanupObjectBox(obj)
                end
            end)
        }
    end

    local function applyStyles()
        for _, data in pairs(playerBoxes) do
            local box = data.box
            box.Thickness = PLAYER_BOX_THICK
            box.Transparency = PLAYER_BOX_TRANSP
            box.Color = PLAYER_BOX_COLOR
        end

        for obj, data in pairs(objectBoxes) do
            local box = data.box
            box.Thickness = OBJECT_BOX_THICK
            box.Transparency = OBJECT_BOX_TRANSP
            box.Color = getObjectColor(obj.Name)
        end
    end

    local function hideAll()
        for _, data in pairs(playerBoxes) do
            data.box.Visible = false
        end
        for _, data in pairs(objectBoxes) do
            data.box.Visible = false
        end
    end

    local function scanInitial()
        local vmFolder = Workspace:FindFirstChild("Viewmodels")
        if vmFolder then
            local vmChildren = vmFolder:GetChildren()
            for i = 1, #vmChildren do
                local model = vmChildren[i]
                if model:IsA("Model") and model.Name ~= "LocalViewmodel" then
                    createPlayerBox(model)
                end
            end
        end

        local children = Workspace:GetChildren()
        for i = 1, #children do
            local child = children[i]
            if child:IsA("Model") then
                createObjectBox(child)
            end
        end
    end

    local function bindWorkspace()
        local vmFolder = Workspace:FindFirstChild("Viewmodels")
        if vmFolder then
            table.insert(connections, vmFolder.ChildAdded:Connect(function(model)
                if model:IsA("Model") and model.Name ~= "LocalViewmodel" then
                    task.delay(0.2, function()
                        createPlayerBox(model)
                    end)
                end
            end))
        end

        table.insert(connections, Workspace.ChildAdded:Connect(function(child)
            if child:IsA("Folder") and child.Name == "Viewmodels" then
                table.insert(connections, child.ChildAdded:Connect(function(model)
                    if model:IsA("Model") and model.Name ~= "LocalViewmodel" then
                        task.delay(0.2, function()
                            createPlayerBox(model)
                        end)
                    end
                end))
                return
            end

            if child:IsA("Model") then
                createObjectBox(child)
            end
        end))

        table.insert(connections, UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then
                return
            end
            if input.KeyCode == Enum.KeyCode.Insert then
                ESP_ENABLED = not ESP_ENABLED
                M.enabled = ESP_ENABLED
                print("ESP " .. (ESP_ENABLED and "ON" or "OFF"))
            end
        end))
    end

    local function renderStep()
        if not currentCamera or not worldToViewportPoint then
            updateCamera()
            if not currentCamera or not worldToViewportPoint then
                hideAll()
                return
            end
        end

        if not ESP_ENABLED then
            hideAll()
            return
        end

        if tickFn() - LAST_TEAM_CACHE > TEAM_CACHE_INTERVAL then
            updateTeamCache()
        end

        if PLAYER_BOX_ENABLED then
            for char, data in pairs(playerBoxes) do
                if not char:IsDescendantOf(Workspace) then
                    cleanupPlayerBox(char)
                else
                    local canRender = true
                    if not data.head or not data.head.Parent or not data.torso or not data.torso.Parent then
                        local newHead, newTorso = resolvePlayerParts(char)
                        if newHead and newTorso then
                            data.head = newHead
                            data.torso = newTorso
                            data.isVisible = newTorso.Transparency <= 0.95
                        else
                            canRender = false
                        end
                    end

                    if not canRender or isTeammate(char) or not data.isVisible then
                        data.box.Visible = false
                    else
                        local ok, x, y, w, h = getPlayerBox2D(data.head, data.torso)
                        if ok then
                            data.box.Position = Vector2new(x, y)
                            data.box.Size = Vector2new(w, h)
                            data.box.Visible = true
                        else
                            data.box.Visible = false
                        end
                    end
                end
            end
        else
            for _, data in pairs(playerBoxes) do
                data.box.Visible = false
            end
        end

        if OBJECT_BOX_ENABLED then
            for obj, data in pairs(objectBoxes) do
                if not obj:IsDescendantOf(Workspace) then
                    cleanupObjectBox(obj)
                else
                    local ok, x, y, w, h = getObjectBox2D(obj)
                    if ok then
                        data.box.Position = Vector2new(x, y)
                        data.box.Size = Vector2new(w, h)
                        data.box.Visible = true
                    else
                        data.box.Visible = false
                    end
                end
            end
        else
            for _, data in pairs(objectBoxes) do
                data.box.Visible = false
            end
        end
    end

    function M:Init()
        if self.initialized then
            return
        end

        updateCamera()
        updateTeamCache()
        scanInitial()
        bindWorkspace()

        mainRenderConn = RunService.RenderStepped:Connect(renderStep)
        self.initialized = true
    end

    function M:SetEnabled(value)
        ESP_ENABLED = value == true
        self.enabled = ESP_ENABLED
    end

    function M:SetTeamCheck(value)
        TEAM_CHECK = value == true
        self.teamCheck = TEAM_CHECK
    end

    function M:SetPlayerBoxEnabled(value)
        PLAYER_BOX_ENABLED = value == true
        self.playerBoxEnabled = PLAYER_BOX_ENABLED
        if not PLAYER_BOX_ENABLED then
            for _, data in pairs(playerBoxes) do
                data.box.Visible = false
            end
        end
    end

    function M:SetObjectBoxEnabled(value)
        OBJECT_BOX_ENABLED = value == true
        self.objectBoxEnabled = OBJECT_BOX_ENABLED
        if not OBJECT_BOX_ENABLED then
            for _, data in pairs(objectBoxes) do
                data.box.Visible = false
            end
        end
    end

    function M:SetPlayerThickness(value)
        PLAYER_BOX_THICK = value
        self.playerThickness = value
        applyStyles()
    end

    function M:SetObjectThickness(value)
        OBJECT_BOX_THICK = value
        self.objectThickness = value
        applyStyles()
    end

    function M:SetPlayerColor(value)
        PLAYER_BOX_COLOR = value
        self.playerColor = value
        applyStyles()
    end

    function M:SetDroneColor(value)
        DRONE_BOX_COLOR = value
        self.droneColor = value
        applyStyles()
    end

    function M:SetClaymoreColor(value)
        CLAYMORE_BOX_COLOR = value
        self.claymoreColor = value
        applyStyles()
    end

    function M:SetProximityColor(value)
        PROXIMITY_ALARM_BOX_COLOR = value
        self.proximityColor = value
        applyStyles()
    end

    function M:SetStickyColor(value)
        STICKY_CAMERA_BOX_COLOR = value
        self.stickyColor = value
        applyStyles()
    end

    function M:RefreshStyles()
        applyStyles()
    end

    function M:Unload()
        ESP_ENABLED = false

        if mainRenderConn then
            mainRenderConn:Disconnect()
            mainRenderConn = nil
        end

        for i = 1, #connections do
            pcall(function()
                connections[i]:Disconnect()
            end)
        end
        clearMap(connections)

        for char in pairs(playerBoxes) do
            cleanupPlayerBox(char)
        end
        for obj in pairs(objectBoxes) do
            cleanupObjectBox(obj)
        end

        self.initialized = false
    end

    return M
end

