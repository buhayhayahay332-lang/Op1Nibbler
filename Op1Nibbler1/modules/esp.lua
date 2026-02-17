return function(_)
    local RunService = game:GetService("RunService")
    local Workspace = game:GetService("Workspace")
    local UserInputService = game:GetService("UserInputService")

    local EXUNYS_URL = "https://raw.githubusercontent.com/Exunys/Exunys-ESP/main/src/ESP.lua"

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

    local teamCache = {}
    local lastCache = 0
    local CACHE_INTERVAL = 0.7

    local playerEntries = {}
    local objectEntries = {}
    local connections = {}
    local mainRenderConn = nil

    local Exunys = {
        player = nil,
        drone = nil,
        claymore = nil,
        proximity = nil,
        sticky = nil,
        loaded = false
    }

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

    local function resolveModelPart(model)
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

            local root = model:FindFirstChild("HumanoidRootPart")
            if root and root:IsA("BasePart") then
                return root
            end

            local torso = model:FindFirstChild("torso")
            if torso and torso:IsA("BasePart") then
                return torso
            end

            local head = model:FindFirstChild("head")
            if head and head:IsA("BasePart") then
                return head
            end

            return model:FindFirstChildWhichIsA("BasePart", true)
        end

        return nil
    end

    local function updateTeamCache()
        teamCache = {}
        for _, v in ipairs(Workspace:GetChildren()) do
            if v:IsA("Highlight") and v.Adornee then
                teamCache[v.Adornee] = true
            end
        end
        lastCache = tick()
    end

    local function isTeammate(model)
        if not TEAM_CHECK then
            return false
        end

        if tick() - lastCache > CACHE_INTERVAL then
            updateTeamCache()
        end

        return teamCache[model] == true
    end
    local exunysSourceCache = nil

    local function getPatchedExunysSource()
        if exunysSourceCache then
            return exunysSourceCache
        end

        local ok, source = pcall(function()
            return game:HttpGet(EXUNYS_URL)
        end)
        if not ok or type(source) ~= "string" then
            return nil
        end

        source = source:gsub(
            'local Connect, Disconnect = __index%(%s*game%s*,%s*"DescendantAdded"%s*%)%.Connect',
            'local Connect = __index(game, "DescendantAdded").Connect\nlocal Disconnect = function(Connection)\n\tif Connection and Connection.Disconnect then\n\t\treturn Connection:Disconnect()\n\tend\nend'
        )

        exunysSourceCache = source
        return exunysSourceCache
    end
    local function createExunysInstance(color, thickness, transparency)
        local source = getPatchedExunysSource()
        if not source then
            return nil
        end

        local ok, env = pcall(function()
            return loadstring(source)()
        end)
        if not ok or type(env) ~= "table" then
            return nil
        end

        if type(env.Settings) == "table" then
            env.Settings.Enabled = true
            env.Settings.PartsOnly = false
            env.Settings.TeamCheck = false
            env.Settings.AliveCheck = false
            env.Settings.LoadConfigOnLaunch = false
            env.Settings.EnableTeamColors = false
            env.Settings.EntityESP = true
        end

        if type(env.Properties) == "table" then
            for _, visuals in pairs(env.Properties) do
                if type(visuals) == "table" and visuals.Enabled ~= nil then
                    visuals.Enabled = false
                end
            end

            if type(env.Properties.Box) == "table" then
                env.Properties.Box.Enabled = true
                env.Properties.Box.RainbowColor = false
                env.Properties.Box.RainbowOutlineColor = false
                env.Properties.Box.Color = color
                env.Properties.Box.Transparency = transparency
                env.Properties.Box.Thickness = thickness
                env.Properties.Box.Filled = false
                env.Properties.Box.Outline = false
            end
        end

        return env
    end

    local function setInstanceStyle(instance, color, thickness, transparency)
        if not instance or type(instance.Properties) ~= "table" then
            return
        end

        local box = instance.Properties.Box
        if type(box) ~= "table" then
            return
        end

        box.Enabled = true
        box.Color = color
        box.Thickness = thickness
        box.Transparency = transparency
        box.Filled = false
        box.Outline = false
    end

    local function loadExunys()
        if Exunys.loaded then
            return Exunys.player and Exunys.drone and Exunys.claymore and Exunys.proximity and Exunys.sticky
        end

        Exunys.player = createExunysInstance(PLAYER_BOX_COLOR, PLAYER_BOX_THICK, PLAYER_BOX_TRANSP)
        Exunys.drone = createExunysInstance(DRONE_BOX_COLOR, OBJECT_BOX_THICK, OBJECT_BOX_TRANSP)
        Exunys.claymore = createExunysInstance(CLAYMORE_BOX_COLOR, OBJECT_BOX_THICK, OBJECT_BOX_TRANSP)
        Exunys.proximity = createExunysInstance(PROXIMITY_ALARM_BOX_COLOR, OBJECT_BOX_THICK, OBJECT_BOX_TRANSP)
        Exunys.sticky = createExunysInstance(STICKY_CAMERA_BOX_COLOR, OBJECT_BOX_THICK, OBJECT_BOX_TRANSP)

        Exunys.loaded = true

        if not Exunys.player or not Exunys.drone or not Exunys.claymore or not Exunys.proximity or not Exunys.sticky then
            warn("[ESP] Failed to initialize one or more Exunys instances")
            return false
        end

        return true
    end

    local function getObjectInstance(name)
        if name == "Drone" then
            return Exunys.drone
        elseif name == "Claymore" then
            return Exunys.claymore
        elseif name == "ProximityAlarm" then
            return Exunys.proximity
        elseif name == "StickyCamera" then
            return Exunys.sticky
        end
        return nil
    end

    local function allowedBoxOnly()
        return {
            ESP = false,
            Tracer = false,
            HeadDot = false,
            Box = true,
            HealthBar = false,
            Chams = false
        }
    end

    local function wrapEntry(entry)
        if not entry or entry.wrapped or not entry.part or not entry.part.Parent then
            return
        end

        local instance = entry.instance
        if not instance then
            return
        end

        pcall(function()
            instance:WrapObject(entry.part, entry.name, allowedBoxOnly(), math.huge)
        end)

        entry.wrapped = true
    end

    local function unwrapEntry(entry)
        if not entry or not entry.wrapped or not entry.part then
            return
        end

        local instance = entry.instance
        if instance then
            pcall(function()
                instance.UnwrapObject(entry.part)
            end)
        end

        entry.wrapped = false
    end

    local function cleanupPlayer(model)
        local entry = playerEntries[model]
        if not entry then
            return
        end

        unwrapEntry(entry)

        if entry.headConn then
            entry.headConn:Disconnect()
        end
        if entry.torsoConn then
            entry.torsoConn:Disconnect()
        end

        playerEntries[model] = nil
    end

    local function cleanupObject(model)
        local entry = objectEntries[model]
        if not entry then
            return
        end

        unwrapEntry(entry)
        objectEntries[model] = nil
    end

    local function createPlayerEntry(model)
        if playerEntries[model] or model.Name == "LocalViewmodel" then
            return
        end

        local head = model:FindFirstChild("head")
        local torso = model:FindFirstChild("torso")
        local part = resolveModelPart(model)
        if not head or not torso or not part then
            return
        end

        local entry = {
            instance = Exunys.player,
            part = part,
            name = model.Name,
            wrapped = false,
            head = head,
            torso = torso,
            isVisible = torso.Transparency <= 0.95
        }

        entry.headConn = head:GetPropertyChangedSignal("Transparency"):Connect(function()
            local cached = playerEntries[model]
            if cached and cached.torso then
                cached.isVisible = cached.torso.Transparency <= 0.95
            end
        end)

        entry.torsoConn = torso:GetPropertyChangedSignal("Transparency"):Connect(function()
            local cached = playerEntries[model]
            if cached and cached.torso then
                cached.isVisible = cached.torso.Transparency <= 0.95
            end
        end)

        playerEntries[model] = entry
    end

    local function createObjectEntry(model)
        if objectEntries[model] then
            return
        end

        local instance = getObjectInstance(model.Name)
        if not instance then
            return
        end

        local part = resolveModelPart(model)
        if not part then
            return
        end

        objectEntries[model] = {
            instance = instance,
            part = part,
            name = model.Name,
            wrapped = false
        }
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
            table.insert(connections, vmFolder.ChildAdded:Connect(function(model)
                if model:IsA("Model") then
                    task.delay(0.25, function()
                        createPlayerEntry(model)
                    end)
                end
            end))
        end

        table.insert(connections, Workspace.ChildAdded:Connect(function(child)
            if child:IsA("Folder") and child.Name == "Viewmodels" then
                table.insert(connections, child.ChildAdded:Connect(function(model)
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

    local function applyStyles()
        setInstanceStyle(Exunys.player, PLAYER_BOX_COLOR, PLAYER_BOX_THICK, PLAYER_BOX_TRANSP)
        setInstanceStyle(Exunys.drone, DRONE_BOX_COLOR, OBJECT_BOX_THICK, OBJECT_BOX_TRANSP)
        setInstanceStyle(Exunys.claymore, CLAYMORE_BOX_COLOR, OBJECT_BOX_THICK, OBJECT_BOX_TRANSP)
        setInstanceStyle(Exunys.proximity, PROXIMITY_ALARM_BOX_COLOR, OBJECT_BOX_THICK, OBJECT_BOX_TRANSP)
        setInstanceStyle(Exunys.sticky, STICKY_CAMERA_BOX_COLOR, OBJECT_BOX_THICK, OBJECT_BOX_TRANSP)
    end

    local function shouldShowPlayer(entry, model)
        if not entry or not entry.part or not entry.part.Parent then
            return false
        end

        if not entry.isVisible then
            return false
        end

        if isTeammate(model) then
            return false
        end

        return isInFrustum(entry.part.Position) and isOnScreen(entry.part.Position)
    end

    local function shouldShowObject(entry, model)
        if not entry or not entry.part or not entry.part.Parent then
            return false
        end

        local refPart = model:IsA("Model") and resolveModelPart(model) or entry.part
        if refPart ~= entry.part and refPart then
            entry.part = refPart
        end

        return isInFrustum(entry.part.Position) and isOnScreen(entry.part.Position)
    end

    local function renderStep()
        if not ESP_ENABLED then
            for _, entry in pairs(playerEntries) do
                unwrapEntry(entry)
            end
            for _, entry in pairs(objectEntries) do
                unwrapEntry(entry)
            end
            return
        end

        if tick() - lastCache > CACHE_INTERVAL then
            updateTeamCache()
        end

        if PLAYER_BOX_ENABLED then
            for model, entry in pairs(playerEntries) do
                if not model:IsDescendantOf(Workspace) then
                    cleanupPlayer(model)
                elseif shouldShowPlayer(entry, model) then
                    wrapEntry(entry)
                else
                    unwrapEntry(entry)
                end
            end
        else
            for _, entry in pairs(playerEntries) do
                unwrapEntry(entry)
            end
        end

        if OBJECT_BOX_ENABLED then
            for model, entry in pairs(objectEntries) do
                if not model:IsDescendantOf(Workspace) then
                    cleanupObject(model)
                elseif shouldShowObject(entry, model) then
                    wrapEntry(entry)
                else
                    unwrapEntry(entry)
                end
            end
        else
            for _, entry in pairs(objectEntries) do
                unwrapEntry(entry)
            end
        end
    end

    function M:Init()
        if self.initialized then
            return
        end

        if not loadExunys() then
            return
        end

        updateTeamCache()
        applyStyles()
        scanInitial()
        bindWorkspace()

        mainRenderConn = RunService.RenderStepped:Connect(renderStep)

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
            for _, entry in pairs(playerEntries) do
                unwrapEntry(entry)
            end
        end
    end

    function M:SetObjectBoxEnabled(value)
        OBJECT_BOX_ENABLED = value == true
        self.objectBoxEnabled = OBJECT_BOX_ENABLED

        if not OBJECT_BOX_ENABLED then
            for _, entry in pairs(objectEntries) do
                unwrapEntry(entry)
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

        for _, conn in ipairs(connections) do
            pcall(function()
                conn:Disconnect()
            end)
        end
        table.clear(connections)

        for model in pairs(playerEntries) do
            cleanupPlayer(model)
        end
        for model in pairs(objectEntries) do
            cleanupObject(model)
        end

        self.initialized = false
    end

    return M
end

