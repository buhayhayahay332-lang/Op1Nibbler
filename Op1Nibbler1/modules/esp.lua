return function(_)
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")
    local UserInputService = game:GetService("UserInputService")

    local tick = tick
    local acos = math.acos
    local rad = math.rad
    local min = math.min
    local max = math.max
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

    local PLAYER_ENTRIES = {}
    local OBJECT_ENTRIES = {}
    local CONNECTIONS = {}
    local RENDER_CONNECTION = nil

    local OBJECT_WHITELIST = {
        Drone = true,
        Claymore = true,
        ProximityAlarm = true,
        StickyCamera = true
    }

    local CACHED_CORNERS = {}
    local CACHED_POINTS = {}
    for i = 1, 8 do
        CACHED_CORNERS[i] = Vector3new(0, 0, 0)
    end
    for i = 1, 4 do
        CACHED_POINTS[i] = Vector3new(0, 0, 0)
    end

    local camera = Workspace.CurrentCamera
    table.insert(CONNECTIONS, Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
        camera = Workspace.CurrentCamera
    end))

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

    local function updateTeamCache()
        TEAM_CACHE = {}
        local children = Workspace:GetChildren()
        for i = 1, #children do
            local obj = children[i]
            if obj:IsA("Highlight") and obj.Adornee then
                TEAM_CACHE[obj.Adornee] = true
            end
        end
        LAST_TEAM_CACHE = tick()
    end

    local function isTeammate(model)
        if not TEAM_CHECK then
            return false
        end
        if tick() - LAST_TEAM_CACHE > TEAM_CACHE_INTERVAL then
            updateTeamCache()
        end
        return TEAM_CACHE[model] == true
    end

    local function isInFrustum(worldPos)
        if not camera then
            return false
        end

        local relativePos = worldPos - camera.CFrame.Position
        local lookDir = camera.CFrame.LookVector
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

    local function onScreen(worldPos)
        if not camera then
            return false
        end
        local _, visible = camera:WorldToViewportPoint(worldPos)
        return visible
    end

    local function createBox(color, thickness, transparency, zIndex)
        local box = Drawing.new("Square")
        box.Visible = false
        box.Filled = false
        box.Color = color
        box.Thickness = thickness
        box.Transparency = transparency
        box.ZIndex = zIndex
        return box
    end

    local function getObjectColorByName(name)
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

    local function resolvePlayerParts(model)
        local head = model:FindFirstChild("head") or model:FindFirstChild("Head")
        local torso = model:FindFirstChild("torso") or model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso") or
            model:FindFirstChild("HumanoidRootPart")

        if not head or not torso then
            return nil, nil
        end
        if not head:IsA("BasePart") or not torso:IsA("BasePart") then
            return nil, nil
        end

        return head, torso
    end

    local function getPlayerBox2D(head, torso)
        if not head or not torso then
            return false
        end
        local torsoPos = torso.Position
        if not isInFrustum(torsoPos) or not onScreen(torsoPos) then
            return false
        end

        local hsx, hsy = head.Size.X * 0.5, head.Size.Y * 0.5
        local tsx, tsy = torso.Size.X * 0.5, torso.Size.Y * 0.5

        CACHED_POINTS[1] = head.Position + Vector3new(-hsx, hsy, 0)
        CACHED_POINTS[2] = head.Position + Vector3new(hsx, hsy, 0)
        CACHED_POINTS[3] = torso.Position + Vector3new(-tsx, -tsy, 0)
        CACHED_POINTS[4] = torso.Position + Vector3new(tsx, -tsy, 0)

        local minX, minY = huge, huge
        local maxX, maxY = -huge, -huge
        local anyVisible = false

        for i = 1, 4 do
            local screenPos, visible = camera:WorldToViewportPoint(CACHED_POINTS[i])
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

    local function getObjectBox2D(model)
        local cf, size = model:GetBoundingBox()
        if not isInFrustum(cf.Position) or not onScreen(cf.Position) then
            return false
        end

        local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
        CACHED_CORNERS[1] = cf * Vector3new(-hx, -hy, -hz)
        CACHED_CORNERS[2] = cf * Vector3new(-hx, -hy, hz)
        CACHED_CORNERS[3] = cf * Vector3new(-hx, hy, -hz)
        CACHED_CORNERS[4] = cf * Vector3new(-hx, hy, hz)
        CACHED_CORNERS[5] = cf * Vector3new(hx, -hy, -hz)
        CACHED_CORNERS[6] = cf * Vector3new(hx, -hy, hz)
        CACHED_CORNERS[7] = cf * Vector3new(hx, hy, -hz)
        CACHED_CORNERS[8] = cf * Vector3new(hx, hy, hz)

        local minX, minY = huge, huge
        local maxX, maxY = -huge, -huge
        local anyVisible = false

        for i = 1, 8 do
            local screenPos, visible = camera:WorldToViewportPoint(CACHED_CORNERS[i])
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

    local function cleanupPlayerEntry(model)
        local entry = PLAYER_ENTRIES[model]
        if not entry then
            return
        end

        if entry.headConn then entry.headConn:Disconnect() end
        if entry.torsoConn then entry.torsoConn:Disconnect() end
        if entry.ancestryConn then entry.ancestryConn:Disconnect() end
        if entry.box then entry.box:Remove() end

        PLAYER_ENTRIES[model] = nil
    end

    local function cleanupObjectEntry(model)
        local entry = OBJECT_ENTRIES[model]
        if not entry then
            return
        end

        if entry.ancestryConn then entry.ancestryConn:Disconnect() end
        if entry.box then entry.box:Remove() end

        OBJECT_ENTRIES[model] = nil
    end

    local function createPlayerEntry(model)
        if PLAYER_ENTRIES[model] or model.Name == "LocalViewmodel" then
            return
        end

        local head, torso = resolvePlayerParts(model)
        if not head or not torso then
            return
        end

        local entry = {
            box = createBox(PLAYER_BOX_COLOR, PLAYER_BOX_THICK, PLAYER_BOX_TRANSP, 2),
            head = head,
            torso = torso,
            isVisible = torso.Transparency <= 0.95
        }

        entry.headConn = head:GetPropertyChangedSignal("Transparency"):Connect(function()
            local cached = PLAYER_ENTRIES[model]
            if cached and cached.torso then
                cached.isVisible = cached.torso.Transparency <= 0.95
            end
        end)

        entry.torsoConn = torso:GetPropertyChangedSignal("Transparency"):Connect(function()
            local cached = PLAYER_ENTRIES[model]
            if cached and cached.torso then
                cached.isVisible = cached.torso.Transparency <= 0.95
            end
        end)

        entry.ancestryConn = model.AncestryChanged:Connect(function(_, parent)
            if not parent then
                cleanupPlayerEntry(model)
            end
        end)

        PLAYER_ENTRIES[model] = entry
    end

    local function createObjectEntry(model)
        if OBJECT_ENTRIES[model] then
            return
        end

        if not OBJECT_WHITELIST[model.Name] then
            return
        end

        OBJECT_ENTRIES[model] = {
            box = createBox(getObjectColorByName(model.Name), OBJECT_BOX_THICK, OBJECT_BOX_TRANSP, 3),
            ancestryConn = model.AncestryChanged:Connect(function(_, parent)
                if not parent then
                    cleanupObjectEntry(model)
                end
            end)
        }
    end

    local function applyStyles()
        for _, entry in pairs(PLAYER_ENTRIES) do
            local box = entry.box
            box.Color = PLAYER_BOX_COLOR
            box.Thickness = PLAYER_BOX_THICK
            box.Transparency = PLAYER_BOX_TRANSP
        end

        for model, entry in pairs(OBJECT_ENTRIES) do
            local box = entry.box
            box.Color = getObjectColorByName(model.Name)
            box.Thickness = OBJECT_BOX_THICK
            box.Transparency = OBJECT_BOX_TRANSP
        end
    end

    local function scanInitial()
        local vmFolder = Workspace:FindFirstChild("Viewmodels")
        if vmFolder then
            local vmChildren = vmFolder:GetChildren()
            for i = 1, #vmChildren do
                local model = vmChildren[i]
                if model:IsA("Model") then
                    createPlayerEntry(model)
                end
            end
        end

        local children = Workspace:GetChildren()
        for i = 1, #children do
            local child = children[i]
            if child:IsA("Model") then
                createObjectEntry(child)
            end
        end
    end

    local function bindWorkspace()
        local vmFolder = Workspace:FindFirstChild("Viewmodels")
        if vmFolder then
            table.insert(CONNECTIONS, vmFolder.ChildAdded:Connect(function(model)
                if model:IsA("Model") then
                    task.delay(0.25, function()
                        createPlayerEntry(model)
                    end)
                end
            end))
        end

        table.insert(CONNECTIONS, Workspace.ChildAdded:Connect(function(child)
            if child:IsA("Folder") and child.Name == "Viewmodels" then
                table.insert(CONNECTIONS, child.ChildAdded:Connect(function(model)
                    if model:IsA("Model") then
                        task.delay(0.25, function()
                            createPlayerEntry(model)
                        end)
                    end
                end))
                return
            end

            if child:IsA("Model") then
                createObjectEntry(child)
            end
        end))
    end

    local function hideAll()
        for _, entry in pairs(PLAYER_ENTRIES) do
            entry.box.Visible = false
        end
        for _, entry in pairs(OBJECT_ENTRIES) do
            entry.box.Visible = false
        end
    end

    local function renderStep()
        if not camera then
            camera = Workspace.CurrentCamera
            if not camera then
                hideAll()
                return
            end
        end

        if not ESP_ENABLED then
            hideAll()
            return
        end

        if tick() - LAST_TEAM_CACHE > TEAM_CACHE_INTERVAL then
            updateTeamCache()
        end

        if PLAYER_BOX_ENABLED then
            for model, entry in pairs(PLAYER_ENTRIES) do
                if not model:IsDescendantOf(Workspace) then
                    cleanupPlayerEntry(model)
                else
                    local canRender = true
                    if not entry.head or not entry.head.Parent or not entry.torso or not entry.torso.Parent then
                        local newHead, newTorso = resolvePlayerParts(model)
                        if newHead and newTorso then
                            entry.head = newHead
                            entry.torso = newTorso
                            entry.isVisible = newTorso.Transparency <= 0.95
                        else
                            canRender = false
                        end
                    end

                    if not canRender or isTeammate(model) or not entry.isVisible then
                        entry.box.Visible = false
                    else
                        local ok, x, y, w, h = getPlayerBox2D(entry.head, entry.torso)
                        if ok then
                            entry.box.Position = Vector2new(x, y)
                            entry.box.Size = Vector2new(w, h)
                            entry.box.Visible = true
                        else
                            entry.box.Visible = false
                        end
                    end
                end
            end
        else
            for _, entry in pairs(PLAYER_ENTRIES) do
                entry.box.Visible = false
            end
        end

        if OBJECT_BOX_ENABLED then
            for model, entry in pairs(OBJECT_ENTRIES) do
                if not model:IsDescendantOf(Workspace) then
                    cleanupObjectEntry(model)
                else
                    local ok, x, y, w, h = getObjectBox2D(model)
                    if ok then
                        entry.box.Position = Vector2new(x, y)
                        entry.box.Size = Vector2new(w, h)
                        entry.box.Visible = true
                    else
                        entry.box.Visible = false
                    end
                end
            end
        else
            for _, entry in pairs(OBJECT_ENTRIES) do
                entry.box.Visible = false
            end
        end
    end

    function M:Init()
        if self.initialized then
            return
        end

        updateTeamCache()
        scanInitial()
        bindWorkspace()

        RENDER_CONNECTION = RunService.RenderStepped:Connect(renderStep)

        table.insert(CONNECTIONS, UserInputService.InputBegan:Connect(function(input, gpe)
            if gpe then
                return
            end
            if input.KeyCode == Enum.KeyCode.Insert then
                ESP_ENABLED = not ESP_ENABLED
                M.enabled = ESP_ENABLED
                print("ESP " .. (ESP_ENABLED and "ON" or "OFF"))
            end
        end))

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
            for _, entry in pairs(PLAYER_ENTRIES) do
                entry.box.Visible = false
            end
        end
    end

    function M:SetObjectBoxEnabled(value)
        OBJECT_BOX_ENABLED = value == true
        self.objectBoxEnabled = OBJECT_BOX_ENABLED
        if not OBJECT_BOX_ENABLED then
            for _, entry in pairs(OBJECT_ENTRIES) do
                entry.box.Visible = false
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

        if RENDER_CONNECTION then
            RENDER_CONNECTION:Disconnect()
            RENDER_CONNECTION = nil
        end

        for i = 1, #CONNECTIONS do
            pcall(function()
                CONNECTIONS[i]:Disconnect()
            end)
        end
        table.clear(CONNECTIONS)

        for model in pairs(PLAYER_ENTRIES) do
            cleanupPlayerEntry(model)
        end
        for model in pairs(OBJECT_ENTRIES) do
            cleanupObjectEntry(model)
        end

        self.initialized = false
    end

    return M
end

