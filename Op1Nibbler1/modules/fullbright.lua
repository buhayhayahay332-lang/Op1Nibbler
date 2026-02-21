return function(ctx)
    local Runtime = ctx and ctx.Runtime or {}
    local cloneref = Runtime.cloneref or cloneref or function(obj)
        return obj
    end
    local Services = ctx and ctx.Services or {}

    local M = {
        enabled = false,
        brightness = 1,
        clockTime = 12,
        fogEnd = 786543,
        globalShadows = false,
        ambient = Color3.fromRGB(178, 178, 178)
    }

    local lighting = Services.Lighting or cloneref(game:GetService("Lighting"))
    local fullbrightSettings = {
        Brightness = 1,
        ClockTime = 12,
        FogEnd = 786543,
        GlobalShadows = false,
        Ambient = Color3.fromRGB(178, 178, 178)
    }

    local function applyLighting(settings)
        for property, value in pairs(settings) do
            lighting[property] = value
        end
    end

    local function ensureInitialized()
        if _G.FullBrightExecuted then
            return
        end

        _G.FullBrightEnabled = false
        _G.NormalLightingSettings = {
            Brightness = lighting.Brightness,
            ClockTime = lighting.ClockTime,
            FogEnd = lighting.FogEnd,
            GlobalShadows = lighting.GlobalShadows,
            Ambient = lighting.Ambient
        }

        local function setupPropertyMonitor(property)
            lighting:GetPropertyChangedSignal(property):Connect(function()
                local current = lighting[property]
                local fullbrightValue = fullbrightSettings[property]
                if current ~= fullbrightValue and current ~= _G.NormalLightingSettings[property] then
                    _G.NormalLightingSettings[property] = current
                    if _G.FullBrightEnabled then
                        lighting[property] = fullbrightValue
                    end
                end
            end)
        end

        for property in pairs(fullbrightSettings) do
            setupPropertyMonitor(property)
        end

        applyLighting(fullbrightSettings)

        task.spawn(function()
            repeat
                task.wait()
            until _G.FullBrightEnabled
            local lastState = _G.FullBrightEnabled
            while task.wait() do
                if _G.FullBrightEnabled ~= lastState then
                    applyLighting(_G.FullBrightEnabled and fullbrightSettings or _G.NormalLightingSettings)
                    lastState = _G.FullBrightEnabled
                end
            end
        end)

        _G.FullBrightExecuted = true
    end

    function M:SetEnabled(state)
        ensureInitialized()
        _G.FullBrightEnabled = state and true or false
        M.enabled = _G.FullBrightEnabled
        applyLighting(_G.FullBrightEnabled and fullbrightSettings or _G.NormalLightingSettings)
    end

    function M:SetBrightness(value)
        fullbrightSettings.Brightness = value
        self.brightness = value
        if self.enabled then
            lighting.Brightness = value
        end
    end

    function M:SetClockTime(value)
        fullbrightSettings.ClockTime = value
        self.clockTime = value
        if self.enabled then
            lighting.ClockTime = value
        end
    end

    function M:SetFogEnd(value)
        fullbrightSettings.FogEnd = value
        self.fogEnd = value
        if self.enabled then
            lighting.FogEnd = value
        end
    end

    function M:SetGlobalShadows(value)
        fullbrightSettings.GlobalShadows = value and true or false
        self.globalShadows = fullbrightSettings.GlobalShadows
        if self.enabled then
            lighting.GlobalShadows = self.globalShadows
        end
    end

    function M:SetAmbient(value)
        fullbrightSettings.Ambient = value
        self.ambient = value
        if self.enabled then
            lighting.Ambient = value
        end
    end

    function M:Toggle()
        self:SetEnabled(not (_G.FullBrightEnabled == true))
    end

    return M
end
