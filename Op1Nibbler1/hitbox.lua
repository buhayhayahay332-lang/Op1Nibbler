local USE_PROPERTY_SPOOFING = true

local cloneref = cloneref or function(obj) return obj end
local clonefunction = clonefunction or function(fn) return fn end
local newcclosure_safe = newcclosure or function(f) return f end
local hookfunction_safe = hookfunction or function(f) return f end

local Workspace = cloneref(game:GetService("Workspace"))
local task_delay = clonefunction(task.delay)
local table_insert = clonefunction(table.insert)
local tick_clock = clonefunction(tick)
local pairs_iter = clonefunction(pairs)
local ipairs_iter = clonefunction(ipairs)
local Vector3_new = clonefunction(Vector3.new)
local Color3_fromRGB = clonefunction(Color3.fromRGB)
local Instance_new = clonefunction(Instance.new)

local Module = {
    _initialized = false,
    _enabled = false,
    _teamCheck = true,
    _globalConnections = {},
    _viewmodelConnections = {},
    _modifiedHeads = {},
    _originalData = {},
    _teamCache = {},
    _lastCacheUpdate = 0,
    _cacheInterval = 0.5,
    _viewmodelsFolder = nil,
    settings = {
        hitboxSize = 5,
        hitboxTransparency = 0.9,
        hitboxColor = Color3_fromRGB(255, 0, 0),
    },
}

local function disconnectConn(conn)
    if conn then
        pcall(function() conn:Disconnect() end)
    end
end

local function disconnectAll(list)
    for _, conn in ipairs_iter(list) do
        disconnectConn(conn)
    end
    table.clear(list)
end

function Module:_bindHooks()
    if self._hooksBound then
        return
    end

    local old_GetPropertyChangedSignal
    old_GetPropertyChangedSignal = hookfunction_safe(game.GetPropertyChangedSignal, newcclosure_safe(function(selfObj, property)
        if Module._originalData[selfObj] and (property == "Size" or property == "Transparency" or property == "Color") then
            return Instance_new("BindableEvent").Event
        end
        return old_GetPropertyChangedSignal(selfObj, property)
    end))

    if USE_PROPERTY_SPOOFING then
        local getrawmetatable_safe = getrawmetatable
        local setreadonly_safe = setreadonly
        if getrawmetatable_safe and setreadonly_safe then
            local mt = getrawmetatable_safe(game)
            local old_index = mt.__index
            setreadonly_safe(mt, false)
            mt.__index = newcclosure_safe(function(selfObj, key)
                local data = Module._originalData[selfObj]
                if data then
                    if key == "Size" then
                        return data.Size
                    elseif key == "Transparency" then
                        return data.Transparency
                    elseif key == "Color" then
                        return data.Color
                    end
                end
                return old_index(selfObj, key)
            end)
            setreadonly_safe(mt, true)
        end
    end

    self._hooksBound = true
end

function Module:_updateTeamCache()
    self._teamCache = {}
    for _, obj in ipairs_iter(Workspace:GetChildren()) do
        if obj:IsA("Highlight") and obj.Adornee then
            self._teamCache[obj.Adornee] = true
        end
    end
    self._lastCacheUpdate = tick_clock()
end

function Module:_isTeammate(vm)
    if not self._teamCheck then
        return false
    end
    if tick_clock() - self._lastCacheUpdate > self._cacheInterval then
        self:_updateTeamCache()
    end
    return self._teamCache[vm] == true
end

function Module:_shouldModify(vm)
    if not vm or vm.Name == "LocalViewmodel" then
        return false
    end

    local torso = vm:FindFirstChild("torso")
    if not torso or torso.Transparency == 1 then
        return false
    end

    return not self:_isTeammate(vm)
end

function Module:_applyHitbox(head)
    if not self._enabled or not head or head.Name ~= "head" then
        return
    end

    if not self._originalData[head] then
        self._originalData[head] = {
            Size = head.Size,
            Transparency = head.Transparency,
            Color = head.Color,
        }
    end

    local size = self.settings.hitboxSize
    head.Size = Vector3_new(size, size, size)
    head.Transparency = self.settings.hitboxTransparency
    head.Color = self.settings.hitboxColor
    head.CanCollide = false
    head.Massless = true
    self._modifiedHeads[head] = true
end

function Module:_resetHead(head)
    local original = head and self._originalData[head]
    if original then
        head.Size = original.Size
        head.Transparency = original.Transparency
        head.Color = original.Color
        self._originalData[head] = nil
        self._modifiedHeads[head] = nil
    end
end

function Module:_cleanupViewmodel(vm)
    local vmConnections = self._viewmodelConnections[vm]
    if vmConnections then
        disconnectAll(vmConnections)
        self._viewmodelConnections[vm] = nil
    end

    for head in pairs_iter(self._modifiedHeads) do
        if head:IsDescendantOf(vm) or head.Parent == nil then
            self:_resetHead(head)
        end
    end
end

function Module:_refreshViewmodel(vm)
    if self:_shouldModify(vm) then
        local head = vm:FindFirstChild("head")
        if head then self:_applyHitbox(head) end
    else
        local head = vm:FindFirstChild("head")
        if head then self:_resetHead(head) end
    end
end

function Module:_processViewmodel(vm)
    if not vm or not vm:IsA("Model") then
        return
    end

    if self._viewmodelConnections[vm] then
        self:_refreshViewmodel(vm)
        return
    end

    self._viewmodelConnections[vm] = {}
    local vmConnections = self._viewmodelConnections[vm]

    task_delay(0.1, newcclosure_safe(function()
        if self._viewmodelConnections[vm] then
            self:_refreshViewmodel(vm)
        end
    end))

    local childAddedConn = vm.ChildAdded:Connect(newcclosure_safe(function(child)
        if child.Name == "head" then
            task_delay(0.05, newcclosure_safe(function()
                if self._viewmodelConnections[vm] and self:_shouldModify(vm) then
                    self:_applyHitbox(child)
                end
            end))
        elseif child.Name == "torso" then
            task_delay(0.05, newcclosure_safe(function()
                if self._viewmodelConnections[vm] then
                    self:_refreshViewmodel(vm)
                end
            end))
        end
    end))
    table_insert(vmConnections, childAddedConn)

    local ancestryConn = vm.AncestryChanged:Connect(newcclosure_safe(function(_, parent)
        if not parent then
            self:_cleanupViewmodel(vm)
        end
    end))
    table_insert(vmConnections, ancestryConn)
end

function Module:init(force)
    if self._initialized and not force then
        return true
    end

    self._viewmodelsFolder = Workspace:WaitForChild("Viewmodels", 10)
    if not self._viewmodelsFolder then
        return false, "Viewmodels folder not found"
    end

    self:_bindHooks()
    self:_updateTeamCache()

    table_insert(self._globalConnections, self._viewmodelsFolder.ChildAdded:Connect(newcclosure_safe(function(vm)
        if vm:IsA("Model") then
            self:_processViewmodel(vm)
        end
    end)))

    table_insert(self._globalConnections, self._viewmodelsFolder.ChildRemoved:Connect(newcclosure_safe(function(vm)
        if vm:IsA("Model") then
            self:_cleanupViewmodel(vm)
        end
    end)))

    if Workspace.CurrentCamera then
        table_insert(self._globalConnections, Workspace.CurrentCamera.ChildAdded:Connect(newcclosure_safe(function(part)
            if part:IsA("BasePart") and part.Name == "head" then
                self:_resetHead(part)
            end
        end)))
    end

    local localViewmodel = self._viewmodelsFolder:FindFirstChild("LocalViewmodel")
    if localViewmodel then
        table_insert(self._globalConnections, localViewmodel.ChildAdded:Connect(newcclosure_safe(function(child)
            if child.Name == "head" then
                self:_resetHead(child)
            end
        end)))
    end

    for _, vm in ipairs_iter(self._viewmodelsFolder:GetChildren()) do
        if vm:IsA("Model") then
            self:_processViewmodel(vm)
        end
    end

    self._initialized = true
    return true
end

function Module:load(force)
    return self:init(force)
end

function Module:isLoaded()
    return self._initialized
end

function Module:setEnabled(state)
    local okInit, initErr = self:init(false)
    if not okInit then
        return false, initErr
    end

    self._enabled = state == true
    if self._enabled then
        self:_updateTeamCache()
        for _, vm in ipairs_iter(self._viewmodelsFolder:GetChildren()) do
            if vm:IsA("Model") then self:_processViewmodel(vm) end
        end
    else
        for vm in pairs_iter(self._viewmodelConnections) do
            self:_cleanupViewmodel(vm)
        end
    end
    return true
end

function Module:toggle()
    return self:setEnabled(not self._enabled)
end

function Module:setTeamCheck(state)
    self._teamCheck = state == true
    self:_updateTeamCache()
    for vm in pairs_iter(self._viewmodelConnections) do
        self:_refreshViewmodel(vm)
    end
    return true
end

function Module:setSize(size)
    if type(size) ~= "number" or size <= 0 then
        return false, "invalid hitbox size"
    end
    self.settings.hitboxSize = size
    for head in pairs_iter(self._modifiedHeads) do
        if head and head.Parent then
            head.Size = Vector3_new(size, size, size)
        end
    end
    return true
end

function Module:setTransparency(value)
    if type(value) ~= "number" then
        return false, "invalid transparency"
    end
    value = math.clamp(value, 0, 1)
    self.settings.hitboxTransparency = value
    for head in pairs_iter(self._modifiedHeads) do
        if head and head.Parent then
            head.Transparency = value
        end
    end
    return true
end

function Module:setColor(color)
    if typeof(color) ~= "Color3" then
        return false, "invalid color"
    end
    self.settings.hitboxColor = color
    for head in pairs_iter(self._modifiedHeads) do
        if head and head.Parent then
            head.Color = color
        end
    end
    return true
end

function Module:unload()
    self:setEnabled(false)
    disconnectAll(self._globalConnections)
    for vm in pairs_iter(self._viewmodelConnections) do
        self:_cleanupViewmodel(vm)
    end
    self._initialized = false
    return true
end

return Module
