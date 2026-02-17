return function(_)
    local USE_PROPERTY_SPOOFING = true

    -- services
    local cloneref = cloneref or function(obj)
        return obj
    end
    local clonefunction = clonefunction or function(fn)
        return fn
    end
    local Workspace = cloneref(game:GetService("Workspace"))
    local UserInputService = cloneref(game:GetService("UserInputService"))
    local RunService = cloneref(game:GetService("RunService"))
    local task_delay = clonefunction(task.delay)
    local table_insert = clonefunction(table.insert)
    local tick = clonefunction(tick)
    local pairs = clonefunction(pairs)
    local ipairs = clonefunction(ipairs)
    local print = clonefunction(print)
    local Vector3_new = clonefunction(Vector3.new)
    local Color3_fromRGB = clonefunction(Color3.fromRGB)
    local Instance_new = clonefunction(Instance.new)
    local newcclosure = newcclosure or function(f)
        return f
    end

    -- viewmodels folder
    local ViewmodelsFolder = Workspace:WaitForChild("Viewmodels")

    -- settings
    local HITBOX_SIZE = 5
    local HITBOX_TRANSPARENCY = 0.9
    local HITBOX_COLOR = Color3_fromRGB(255, 0, 0)
    local TOGGLE_KEY = Enum.KeyCode.H

    local ENABLED = false
    local globalConnections = {}
    local modifiedHeads = {}
    local originalData = {}
    local viewmodelData = {}

    local M = {
        enabled = ENABLED,
        size = HITBOX_SIZE,
        transparency = HITBOX_TRANSPARENCY,
        color = HITBOX_COLOR,
        teamCheck = true
    }

    -- hooks
    local hookfunction = hookfunction or function(f, r)
        return f
    end

    local old_GetPropertyChangedSignal = hookfunction(game.GetPropertyChangedSignal,
        newcclosure(function(self, property)
            if originalData[self] and (property == "Size" or property == "Transparency" or property == "Color") then
                return Instance_new("BindableEvent").Event
            end
            return old_GetPropertyChangedSignal(self, property)
        end))

    if USE_PROPERTY_SPOOFING then
        local hookmetamethod = hookmetamethod or function()
        end
        local getrawmetatable = getrawmetatable or function()
            return {}
        end
        local setreadonly = setreadonly or function()
        end

        local mt = getrawmetatable(game)
        local old_index = mt.__index
        setreadonly(mt, false)

        mt.__index = newcclosure(function(self, key)
            if originalData[self] then
                if key == "Size" then
                    return originalData[self].Size
                elseif key == "Transparency" then
                    return originalData[self].Transparency
                elseif key == "Color" then
                    return originalData[self].Color
                end
            end
            return old_index(self, key)
        end)

        setreadonly(mt, true)
        print("Property spoofing: ENABLED")
    else
        print("Property spoofing: DISABLED")
    end

    -- team filtering
    local teamCache = {}
    local lastCacheUpdate = 0
    local CACHE_INTERVAL = 0.7
    local UPDATE_INTERVAL = 0.12
    local accumulatedDt = 0

    local updateTeamCache = newcclosure(function()
        teamCache = {}
        for _, obj in ipairs(Workspace:GetChildren()) do
            if obj:IsA("Highlight") and obj.Adornee then
                teamCache[obj.Adornee] = true
            end
        end
    end)

    local isTeammate = newcclosure(function(vm)
        if not M.teamCheck then
            return false
        end
        if tick() - lastCacheUpdate > CACHE_INTERVAL then
            updateTeamCache()
            lastCacheUpdate = tick()
        end
        return teamCache[vm] == true
    end)

    -- hitboxes
    local shouldModify = newcclosure(function(vm, data)
        if not ENABLED then
            return false
        end
        if not vm or not vm:IsA("Model") or not vm:IsDescendantOf(Workspace) then
            return false
        end
        if vm.Name == "LocalViewmodel" then
            return false
        end
        local head = data and data.head or vm:FindFirstChild("head")
        local torso = data and data.torso or vm:FindFirstChild("torso")
        if not head or not torso then
            return false
        end
        if torso.Transparency > 0.95 then
            return false
        end
        return not isTeammate(vm)
    end)

    local applyHitbox = newcclosure(function(head)
        if not ENABLED or not head or head.Name ~= "head" then
            return
        end

        if not originalData[head] then
            originalData[head] = {
                Size = head.Size,
                Transparency = head.Transparency,
                Color = head.Color
            }
        end

        head.Size = Vector3_new(HITBOX_SIZE, HITBOX_SIZE, HITBOX_SIZE)
        head.Transparency = HITBOX_TRANSPARENCY
        head.Color = HITBOX_COLOR
        head.CanCollide = false
        head.Massless = true

        modifiedHeads[head] = true
    end)

    local resetHead = newcclosure(function(head)
        if head and originalData[head] then
            head.Size = originalData[head].Size
            head.Transparency = originalData[head].Transparency
            head.Color = originalData[head].Color

            originalData[head] = nil
            modifiedHeads[head] = nil
        end
    end)

    local syncViewmodelHitbox = newcclosure(function(vm)
        if not vm or not vm:IsA("Model") then
            return
        end

        local data = viewmodelData[vm]
        local head = data and data.head
        if not head then
            head = vm:FindFirstChild("head")
            if data then
                data.head = head
            end
        end
        if not head then
            return
        end

        if shouldModify(vm, data) then
            applyHitbox(head)
        else
            resetHead(head)
        end
    end)

    -- cleanups
    local cleanupViewmodel = newcclosure(function(vm)
        local data = viewmodelData[vm]
        if data then
            for _, conn in ipairs(data.connections) do
                pcall(function()
                    conn:Disconnect()
                end)
            end
            if data.torsoConn then
                pcall(function()
                    data.torsoConn:Disconnect()
                end)
            end
            viewmodelData[vm] = nil
        end

        for head in pairs(modifiedHeads) do
            if head:IsDescendantOf(vm) or head.Parent == nil then
                resetHead(head)
            end
        end
    end)

    -- init
    local bindTorsoWatcher
    bindTorsoWatcher = newcclosure(function(vm)
        local data = viewmodelData[vm]
        if not data then
            return
        end

        if data.torsoConn then
            pcall(function()
                data.torsoConn:Disconnect()
            end)
            data.torsoConn = nil
        end

        if data.torso then
            data.torsoConn = data.torso:GetPropertyChangedSignal("Transparency"):Connect(newcclosure(function()
                syncViewmodelHitbox(vm)
            end))
        end
    end)

    local processViewmodel = newcclosure(function(vm)
        if not vm or not vm:IsA("Model") or vm.Name == "LocalViewmodel" then
            return
        end

        if viewmodelData[vm] then
            return
        end

        local data = {
            head = vm:FindFirstChild("head"),
            torso = vm:FindFirstChild("torso"),
            torsoConn = nil,
            connections = {}
        }
        viewmodelData[vm] = data
        bindTorsoWatcher(vm)

        task_delay(0.1, newcclosure(function()
            syncViewmodelHitbox(vm)
        end))

        local childAddedConn = vm.ChildAdded:Connect(newcclosure(function(child)
            if child.Name == "head" or child.Name == "torso" then
                if child.Name == "head" then
                    data.head = child
                else
                    data.torso = child
                    bindTorsoWatcher(vm)
                end
                task_delay(0.05, newcclosure(function()
                    syncViewmodelHitbox(vm)
                end))
            end
        end))
        table_insert(data.connections, childAddedConn)

        local childRemovedConn = vm.ChildRemoved:Connect(newcclosure(function(child)
            if child.Name == "head" or child.Name == "torso" then
                if child.Name == "head" then
                    data.head = nil
                else
                    data.torso = nil
                    bindTorsoWatcher(vm)
                end
                task_delay(0.05, newcclosure(function()
                    syncViewmodelHitbox(vm)
                end))
            end
        end))
        table_insert(data.connections, childRemovedConn)

        local ancestryConn = vm.AncestryChanged:Connect(newcclosure(function(_, parent)
            if not parent then
                cleanupViewmodel(vm)
            end
        end))
        table_insert(data.connections, ancestryConn)
    end)

    -- toggles
    local toggle = newcclosure(function()
        ENABLED = not ENABLED
        M.enabled = ENABLED
        print(ENABLED and "Hitbox Expander: ENABLED" or "Hitbox Expander: DISABLED")

        if ENABLED then
            updateTeamCache()
            lastCacheUpdate = tick()
            accumulatedDt = 0
            for _, vm in ipairs(ViewmodelsFolder:GetChildren()) do
                if vm:IsA("Model") then
                    processViewmodel(vm)
                    syncViewmodelHitbox(vm)
                end
            end
        else
            for vm in pairs(viewmodelData) do
                cleanupViewmodel(vm)
            end
        end
    end)

    -- players hitbox init
    updateTeamCache()

    table_insert(globalConnections, ViewmodelsFolder.ChildAdded:Connect(newcclosure(function(vm)
        if ENABLED and vm:IsA("Model") then
            processViewmodel(vm)
        end
    end)))

    table_insert(globalConnections, ViewmodelsFolder.ChildRemoved:Connect(newcclosure(function(vm)
        if vm:IsA("Model") then
            cleanupViewmodel(vm)
        end
    end)))

    table_insert(globalConnections, RunService.Heartbeat:Connect(newcclosure(function(dt)
        if not ENABLED then
            return
        end

        accumulatedDt = accumulatedDt + dt
        if accumulatedDt < UPDATE_INTERVAL then
            return
        end
        accumulatedDt = 0

        if tick() - lastCacheUpdate > CACHE_INTERVAL then
            updateTeamCache()
            lastCacheUpdate = tick()
        end

        for vm in pairs(viewmodelData) do
            syncViewmodelHitbox(vm)
        end
    end)))

    table_insert(globalConnections, Workspace.CurrentCamera.ChildAdded:Connect(newcclosure(function(part)
        if part:IsA("BasePart") and part.Name == "head" then
            resetHead(part)
        end
    end)))

    local localViewmodel = ViewmodelsFolder:FindFirstChild("LocalViewmodel")
    if localViewmodel then
        local conn = localViewmodel.ChildAdded:Connect(newcclosure(function(child)
            if child.Name == "head" then
                resetHead(child)
            end
        end))
        table_insert(globalConnections, conn)
    end

    -- Toggle keybind
    table_insert(globalConnections, UserInputService.InputBegan:Connect(
        newcclosure(function(input, processed)
            if not processed and input.KeyCode == TOGGLE_KEY then
                toggle()
            end
        end)))

    function M:SetEnabled(state)
        state = state and true or false
        if state ~= ENABLED then
            toggle()
        end
    end

    function M:SetTeamCheck(value)
        M.teamCheck = value and true or false
        if ENABLED then
            updateTeamCache()
            lastCacheUpdate = tick()
            for vm in pairs(viewmodelData) do
                syncViewmodelHitbox(vm)
            end
        end
    end

    function M:SetSize(value)
        HITBOX_SIZE = value
        M.size = value
        if ENABLED then
            for head in pairs(modifiedHeads) do
                if head and head.Parent then
                    head.Size = Vector3_new(HITBOX_SIZE, HITBOX_SIZE, HITBOX_SIZE)
                end
            end
        end
    end

    function M:SetTransparency(value)
        HITBOX_TRANSPARENCY = value
        M.transparency = value
        if ENABLED then
            for head in pairs(modifiedHeads) do
                if head and head.Parent then
                    head.Transparency = HITBOX_TRANSPARENCY
                end
            end
        end
    end

    function M:SetColor(value)
        HITBOX_COLOR = value
        M.color = value
        if ENABLED then
            for head in pairs(modifiedHeads) do
                if head and head.Parent then
                    head.Color = HITBOX_COLOR
                end
            end
        end
    end

    return M
end
