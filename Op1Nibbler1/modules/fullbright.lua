return function(_)
    local M = {
        enabled = false
    }

    local lighting = game:GetService("Lighting")
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

        local function setupPropertyMonitor(property, fullbrightValue)
            lighting:GetPropertyChangedSignal(property):Connect(function()
                local current = lighting[property]
                if current ~= fullbrightValue and current ~= _G.NormalLightingSettings[property] then
                    _G.NormalLightingSettings[property] = current
                    if _G.FullBrightEnabled then
                        lighting[property] = fullbrightValue
                    end
                end
            end)
        end

        for property, value in pairs(fullbrightSettings) do
            setupPropertyMonitor(property, value)
        end

        applyLighting(fullbrightSettings)

        task.spawn(function()
            repeat task.wait() until _G.FullBrightEnabled
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

    function M:Toggle()
        self:SetEnabled(not (_G.FullBrightEnabled == true))
    end

    return M
end
