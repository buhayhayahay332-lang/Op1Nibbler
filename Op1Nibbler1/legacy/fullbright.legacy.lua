if not _G.FullBrightExecuted then
    _G.FullBrightEnabled = false
    
    local lighting = game:GetService("Lighting")
    
    -- Store original settings
    _G.NormalLightingSettings = {
        Brightness = lighting.Brightness,
        ClockTime = lighting.ClockTime,
        FogEnd = lighting.FogEnd,
        GlobalShadows = lighting.GlobalShadows,
        Ambient = lighting.Ambient
    }
    
    -- Fullbright settings
    local fullbrightSettings = {
        Brightness = 1,
        ClockTime = 12,
        FogEnd = 786543,
        GlobalShadows = false,
        Ambient = Color3.fromRGB(178, 178, 178)
    }
    
    -- Apply lighting settings
    local function applyLighting(settings)
        for property, value in pairs(settings) do
            lighting[property] = value
        end
    end
    
    -- Monitor property changes and enforce fullbright
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
    
    -- Setup monitors for all properties
    for property, value in pairs(fullbrightSettings) do
        setupPropertyMonitor(property, value)
    end
    
    -- Apply initial fullbright
    applyLighting(fullbrightSettings)
    
    -- Toggle handler
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

_G.FullBrightEnabled = not _G.FullBrightEnabled