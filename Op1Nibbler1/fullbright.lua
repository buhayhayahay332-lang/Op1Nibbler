local Lighting = game:GetService("Lighting")

local Module = {
    _initialized = false,
    _enabled = false,
    _connections = {},
    _normal = nil,
    _fullbright = {
        Brightness = 1,
        ClockTime = 12,
        FogEnd = 786543,
        GlobalShadows = false,
        Ambient = Color3.fromRGB(178, 178, 178),
    },
}

local function disconnectAll(connections)
    for _, conn in ipairs(connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(connections)
end

function Module:_captureNormal()
    self._normal = {
        Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime,
        FogEnd = Lighting.FogEnd,
        GlobalShadows = Lighting.GlobalShadows,
        Ambient = Lighting.Ambient,
    }
end

function Module:_apply(settings)
    for property, value in pairs(settings) do
        Lighting[property] = value
    end
end

function Module:_bindMonitors()
    disconnectAll(self._connections)
    for property in pairs(self._fullbright) do
        local conn = Lighting:GetPropertyChangedSignal(property):Connect(function()
            local current = Lighting[property]
            if self._enabled then
                local targetValue = self._fullbright[property]
                if current ~= targetValue then
                    Lighting[property] = targetValue
                end
                return
            end

            if self._normal and current ~= self._normal[property] then
                self._normal[property] = current
            end
        end)
        table.insert(self._connections, conn)
    end
end

function Module:init(force)
    if self._initialized and not force then
        return true
    end

    self:_captureNormal()
    self:_bindMonitors()
    self._initialized = true
    return true
end

function Module:load(force)
    return self:init(force)
end

function Module:isLoaded()
    return self._initialized
end

function Module:isEnabled()
    return self._enabled == true
end

function Module:setEnabled(state)
    local okInit, initErr = self:init(false)
    if not okInit then
        return false, initErr
    end

    self._enabled = state == true
    if self._enabled then
        self:_apply(self._fullbright)
    else
        self:_apply(self._normal)
    end
    return true
end

function Module:toggle()
    return self:setEnabled(not self._enabled)
end

function Module:setSetting(property, value)
    local okInit, initErr = self:init(false)
    if not okInit then
        return false, initErr
    end

    if self._fullbright[property] == nil then
        return false, "unknown fullbright setting: " .. tostring(property)
    end

    self._fullbright[property] = value
    if self._enabled then
        Lighting[property] = value
    end
    return true
end

function Module:getSettings()
    return self._fullbright
end

function Module:destroy()
    self:setEnabled(false)
    disconnectAll(self._connections)
    self._initialized = false
end

return Module
