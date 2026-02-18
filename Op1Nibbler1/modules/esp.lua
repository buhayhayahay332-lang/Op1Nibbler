return function(_)
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")
    local UserInputService = game:GetService("UserInputService")

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

    local CACHED_CORNERS = table.create(8)
    local CACHED_POINTS = table.create(4)

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

    local function getCamera()
        return Workspace.CurrentCamera
    end

    local function isOnScreen(worldPos)
        local camera = getCamera()
        if not camera then
            return false
        end
        local _, onScreen = camera:WorldToViewportPoint(worldPos)
        return onScreen
    end

    local function isInFrustum(worldPos)
        local camera = getCamera()
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

        local angle = math.acos(math.min(1, relativePos.Unit:Dot(lookDir)))
        return angle < math.rad(60)
    end

    local function updateTeamCache()
        TEAM_CACHE = {}
        for _, obj in ipairs(Workspace:GetChildren()) do
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

    local function createBox(color, thickness, transparency, zindex)
        local box = Drawing.new("Square")
        box.Visible = false
        box.Filled = false
        box.Color = color
        box.Thickness = thickness
        box.Transparency = transparency
        box.ZIndex = zindex
        return box
    end

    local function resolveObjectPart(model)
        if not model then
            return nil
        end

        if model:IsA("BasePart") then
            return model
        end

        if model:IsA("Model") then
            if model.PrimaryPart then
                return model.PrimaryPart
            end
            return model:FindFirstChildWhichIsA("BasePart", true)
        end

        return nil
    end

    local function resolvePlayerParts(model)
        if not model or not model:IsA("Model") then
            return nil, nil
        end

        local head = model:FindFirstChild("head")
        local torso = model:FindFirstChild("torso")

        if not head then
            head = model:FindFirstChild("Head")
        end
        if not torso then
            torso = model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso") or model:FindFirstChild("HumanoidRootPart")
        end

        if not head or not torso then
            return nil, nil
        end

        if not head:IsA("BasePart") or not torso:IsA("BasePart") then
            return nil, nil
        end

        return head, torso
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

    local function getObjectBox2D(model)
        local camera = getCamera()
        if not camera then
            return false
        end

        local cf, size = model:GetBoundingBox()
        if not isInFrustum(cf.Position) or not isOnScreen(cf.Position) then
            return false
        end

        local hx, hy, hz = size.X * 0.5, size.Y * 0.5, size.Z * 0.5
        CACHED_CORNERS[1] = cf * Vector3.new(-hx, -hy, -hz)
        CACHED_CORNERS[2] = cf * Vector3.new(-hx, -hy, hz)
        CACHED_CORNERS[3] = cf * Vector3.new(-hx, hy, -hz)
        CACHED_CORNERS[4] = cf * Vector3.new(-hx, hy, hz)
        CACHED_CORNERS[5] = cf * Vector3.new(hx, -hy, -hz)
        CACHED_CORNERS[6] = cf * Vector3.new(hx, -hy, hz)
        CACHED_CORNERS[7] = cf * Vector3.new(hx, hy, -hz)
        CACHED_CORNERS[8] = cf * Vector3.new(hx, hy, hz)

        local minX, minY = math.huge, math.huge
        local maxX, maxY = -math.huge, -math.huge
        local visible = false

        for i = 1, 8 do
            local screenPos, onScreen = camera:WorldToViewportPoint(CACHED_CORNERS[i])
            if onScreen then
                visible = true
                local x, y = screenPos.X, screenPos.Y
                if x < minX then minX = x end
                if y < minY then minY = y end
                if x > maxX then maxX = x end
                if y > maxY then maxY = y end
            end
        end

        if not visible then
            return false
        end

        return true, minX, minY, maxX - minX, maxY - minY
    end

    local function getPlayerBox2D(head, torso)
        local camera = getCamera()
        if not camera then
            return false
        end

        local torsoPos = torso.Position
        if not isInFrustum(torsoPos) or not isOnScreen(torsoPos) then
            return false
        end

        local hsx, hsy = head.Size.X * 0.5, head.Size.Y * 0.5
        local tsx, tsy = torso.Size.X * 0.5, torso.Size.Y * 0.5

        CACHED_POINTS[1] = head.Position + Vector3.new(-hsx, hsy, 0)
        CACHED_POINTS[2] = head.Position + Vector3.new(hsx, hsy, 0)
        CACHED_POINTS[3] = torso.Position + Vector3.new(-tsx, -tsy, 0)
        CACHED_POINTS[4] = torso.Position + Vector3.new(tsx, -tsy, 0)

        local minX, minY = math.huge, math.huge
        local maxX, maxY = -math.huge, -math.huge
        local visible = false

        for i = 1, 4 do
            local screenPos, onScreen = camera:WorldToViewportPoint(CACHED_POINTS[i])
            if onScreen then
                visible = true
                local x, y = screenPos.X, screenPos.Y
                if x < minX then minX = x end
                if y < minY then minY = y end
                if x > maxX then maxX = x end
                if y > maxY then maxY = y end
            end
        end

        if not visible then
            return false
        end

        local padding = 3
        return true, minX - padding, minY - padding, (maxX - minX) + padding * 2, (maxY - minY) + padding * 2
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

        local color = getObjectColorByName(model.Name)
        if not color then
            return
        end

        local part = resolveObjectPart(model)
        if not part then
            return
        end

        local entry = {
            part = part,
            box = createBox(color, OBJECT_BOX_THICK, OBJECT_BOX_TRANSP, 3)
        }

        entry.ancestryConn = model.AncestryChanged:Connect(function(_, parent)
            if not parent then
                cleanupObjectEntry(model)
            end
        end)

        OBJECT_ENTRIES[model] = entry
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
            box.Thickness = OBJECT_BOX_THICK
            box.Transparency = OBJECT_BOX_TRANSP

            local c = getObjectColorByName(model.Name)
            if c then
                box.Color = c
            end
        end
    end

    local function scanInitial()
        local vmFolder = Workspace:FindFirstChild("Viewmodels")
        if vmFolder then
            for _, model in ipairs(vmFolder:GetChildren()) do
                if model:IsA("Model") then
                    createPlayerEntry(model)
                end
            end
        end

        for _, child in ipairs(Workspace:GetChildren()) do
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

    local function renderStep()
        if not ESP_ENABLED then
            for _, entry in pairs(PLAYER_ENTRIES) do
                entry.box.Visible = false
            end
            for _, entry in pairs(OBJECT_ENTRIES) do
                entry.box.Visible = false
            end
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
                    if (not entry.head or not entry.head.Parent) or (not entry.torso or not entry.torso.Parent) then
                        local newHead, newTorso = resolvePlayerParts(model)
                        if not newHead or not newTorso then
                            entry.box.Visible = false
                            goto continue_players
                        end
                        entry.head = newHead
                        entry.torso = newTorso
                        entry.isVisible = newTorso.Transparency <= 0.95
                    end

                    if isTeammate(model) or not entry.isVisible then
                        entry.box.Visible = false
                    else
                        local ok, x, y, w, h = getPlayerBox2D(entry.head, entry.torso)
                        if ok then
                            entry.box.Position = Vector2.new(x, y)
                            entry.box.Size = Vector2.new(w, h)
                            entry.box.Visible = true
                        else
                            entry.box.Visible = false
                        end
                    end
                end
                ::continue_players::
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
                    if not entry.part or not entry.part.Parent then
                        entry.part = resolveObjectPart(model)
                        if not entry.part then
                            entry.box.Visible = false
                            goto continue_objects
                        end
                    end

                    local ok, x, y, w, h = getObjectBox2D(model)
                    if ok then
                        entry.box.Position = Vector2.new(x, y)
                        entry.box.Size = Vector2.new(w, h)
                        entry.box.Visible = true
                    else
                        entry.box.Visible = false
                    end
                end
                ::continue_objects::
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

        for _, conn in ipairs(CONNECTIONS) do
            pcall(function()
                conn:Disconnect()
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
