local UILIB_URLS = {
    "https://raw.githubusercontent.com/suannelson123/UiLib/main/source.luau",
    "https://raw.githubusercontent.com/4lpaca-pin/CompKiller/refs/heads/main/src/source.luau",
}

local MODULE_SOURCES = {
    fullbright = { local_path = "fullbright.lua", url = "https://github.com/buhayhayahay332-lang/Op1Nibbler/raw/refs/heads/main/Op1Nibbler1/fullbright.lua" },
    gun_modification = { local_path = "gun_modification.lua", url = "https://github.com/buhayhayahay332-lang/Op1Nibbler/raw/refs/heads/main/Op1Nibbler1/gun_modification.lua" },
    hitbox = { local_path = "hitbox.lua", url = "https://github.com/buhayhayahay332-lang/Op1Nibbler/raw/refs/heads/main/Op1Nibbler1/hitbox.lua" },
    player_esp_gadgets = { local_path = "player_esp_gadgets.lua", url = "https://github.com/buhayhayahay332-lang/Op1Nibbler/raw/refs/heads/main/Op1Nibbler1/player_esp_gadgets.lua" },
    silent_aim = { local_path = "silent_aim.lua", url = "https://github.com/buhayhayahay332-lang/Op1Nibbler/raw/refs/heads/main/Op1Nibbler1/silent_aim.lua" },
}

local moduleCache = {}

local function log(msg)
    print("[OP1] " .. tostring(msg))
end

local function compile(source, chunkName)
    local compiler = loadstring or load
    if type(compiler) ~= "function" then
        return nil, "loadstring/load unavailable"
    end

    local okLoad, chunkOrErr = pcall(compiler, source, "@" .. tostring(chunkName))
    if not okLoad or type(chunkOrErr) ~= "function" then
        return nil, "compile error: " .. tostring(chunkOrErr)
    end

    local okRun, resultOrErr = pcall(chunkOrErr)
    if not okRun then
        return nil, "runtime error: " .. tostring(resultOrErr)
    end

    if type(resultOrErr) == "table" then
        return resultOrErr
    end

    return { load = function() return true end }
end

local function readSource(spec)
    if type(readfile) == "function" and spec.local_path then
        local okLocal, localData = pcall(readfile, spec.local_path)
        if okLocal and type(localData) == "string" and localData ~= "" then
            return localData, "local:" .. spec.local_path
        end
    end

    if spec.url and spec.url ~= "" then
        local okUrl, remoteData = pcall(function()
            return game:HttpGet(spec.url)
        end)
        if okUrl and type(remoteData) == "string" and remoteData ~= "" then
            return remoteData, "url:" .. spec.url
        end
    end

    return nil, "no source available"
end

local function initModule(name, forceReload)
    local cached = moduleCache[name]
    if cached and cached.initialized and not forceReload then
        return cached.module
    end

    local spec = MODULE_SOURCES[name]
    if not spec then
        log("unknown module: " .. tostring(name))
        return nil
    end

    local source, sourceInfo = readSource(spec)
    if not source then
        log(name .. " source error -> " .. tostring(sourceInfo))
        return nil
    end

    local moduleObj, loadErr = compile(source, name)
    if not moduleObj then
        log(name .. " load error -> " .. tostring(loadErr))
        return nil
    end

    local okInit, initErr = true, nil
    if type(moduleObj.load) == "function" then
        okInit, initErr = moduleObj:load(forceReload == true)
    elseif type(moduleObj.init) == "function" then
        okInit, initErr = moduleObj:init(forceReload == true)
    end

    if okInit == false then
        log(name .. " init failed -> " .. tostring(initErr))
        return nil
    end

    moduleCache[name] = { initialized = true, module = moduleObj }
    return moduleObj
end

local function withModule(name, callback)
    local moduleObj = initModule(name, false)
    if not moduleObj then
        return false
    end

    local ok, result = pcall(callback, moduleObj)
    if not ok then
        log(name .. " callback error -> " .. tostring(result))
        return false
    end

    return result ~= false
end

local function setSilentAim(state)
    withModule("silent_aim", function(m)
        if type(m.setEnabled) == "function" then
            local okSet, errSet = m:setEnabled(state)
            if okSet == false then
                log("silent aim toggle failed -> " .. tostring(errSet))
            end
        end
    end)
end

local function setSilentAimFov(value)
    withModule("silent_aim", function(m)
        if type(m.setFov) == "function" then m:setFov(value) end
    end)
end

local function setSilentAimSmoothness(value)
    withModule("silent_aim", function(m)
        if type(m.setSmoothness) == "function" then m:setSmoothness(value) end
    end)
end

local function setSilentAimTargets(players, gadgets, cameras)
    withModule("silent_aim", function(m)
        if type(m.setTargeting) == "function" then m:setTargeting(players, gadgets, cameras) end
    end)
end

local function setGunModEnabled(state)
    withModule("gun_modification", function(m)
        if type(m.setEnabled) == "function" then m:setEnabled(state) end
    end)
end

local function setGunModConfig(key, value)
    withModule("gun_modification", function(m)
        if type(m.updateConfig) == "function" then
            m:updateConfig({ [key] = value })
        elseif type(m.config) == "table" then
            m.config[key] = value
        end
    end)
end

local function setEspEnabled(state)
    withModule("player_esp_gadgets", function(m)
        if type(m.setEnabled) == "function" then m:setEnabled(state) end
    end)
end

local function setEspTeamCheck(state)
    withModule("player_esp_gadgets", function(m)
        if type(m.setTeamCheck) == "function" then m:setTeamCheck(state) end
    end)
    withModule("hitbox", function(m)
        if type(m.setTeamCheck) == "function" then m:setTeamCheck(state) end
    end)
end

local function setEspPlayers(state)
    withModule("player_esp_gadgets", function(m)
        if type(m.setPlayerBoxEnabled) == "function" then m:setPlayerBoxEnabled(state) end
    end)
end

local function setEspObjects(state)
    withModule("player_esp_gadgets", function(m)
        if type(m.setObjectBoxEnabled) == "function" then m:setObjectBoxEnabled(state) end
    end)
end

local function setEspPlayerColor(color)
    withModule("player_esp_gadgets", function(m)
        if type(m.setPlayerColor) == "function" then m:setPlayerColor(color) end
    end)
end

local function setEspObjectColor(color)
    withModule("player_esp_gadgets", function(m)
        if type(m.setObjectColor) == "function" then m:setObjectColor(color) end
    end)
end

local function setEspDroneColor(color)
    withModule("player_esp_gadgets", function(m)
        if type(m.setDroneColor) == "function" then m:setDroneColor(color) end
    end)
end

local function setEspClaymoreColor(color)
    withModule("player_esp_gadgets", function(m)
        if type(m.setClaymoreColor) == "function" then m:setClaymoreColor(color) end
    end)
end

local function setEspProximityAlarmColor(color)
    withModule("player_esp_gadgets", function(m)
        if type(m.setProximityAlarmColor) == "function" then m:setProximityAlarmColor(color) end
    end)
end

local function setEspStickyCameraColor(color)
    withModule("player_esp_gadgets", function(m)
        if type(m.setStickyCameraColor) == "function" then m:setStickyCameraColor(color) end
    end)
end

local function setHitboxEnabled(state)
    withModule("hitbox", function(m)
        if type(m.setEnabled) == "function" then m:setEnabled(state) end
    end)
end

local function setHitboxSize(value)
    withModule("hitbox", function(m)
        if type(m.setSize) == "function" then m:setSize(value) end
    end)
end

local function setHitboxTransparency(value)
    withModule("hitbox", function(m)
        if type(m.setTransparency) == "function" then m:setTransparency(value) end
    end)
end

local function setHitboxColor(color)
    withModule("hitbox", function(m)
        if type(m.setColor) == "function" then m:setColor(color) end
    end)
end

local function setFullbright(state)
    withModule("fullbright", function(m)
        if type(m.setEnabled) == "function" then
            m:setEnabled(state)
        elseif type(m.toggle) == "function" then
            m:toggle()
        end
    end)
end

local function setFullbrightSetting(key, value)
    withModule("fullbright", function(m)
        if type(m.setSetting) == "function" then m:setSetting(key, value) end
    end)
end

local function loadUiLibrary()
    local compiler = loadstring or load
    if type(compiler) ~= "function" then
        return nil
    end

    for _, url in ipairs(UILIB_URLS) do
        local okLib, libOrErr = pcall(function()
            local source = game:HttpGet(url)
            local chunk = compiler(source, "@uilib:" .. url)
            if type(chunk) ~= "function" then
                error("ui compile returned non-function")
            end
            return chunk()
        end)

        if okLib and type(libOrErr) == "table" then
            log("UI loaded from: " .. url)
            return libOrErr
        end
    end

    return nil
end

local function addColorPickerSafe(section, config)
    if type(section.AddColorPicker) == "function" then
        local ok, picker = pcall(function()
            return section:AddColorPicker(config)
        end)
        if ok then
            return picker
        end
    end

    if type(section.AddOption) == "function" then
        local okOpt, opt = pcall(function()
            return section:AddOption()
        end)
        if okOpt and type(opt) == "table" and type(opt.AddColorPicker) == "function" then
            pcall(function()
                opt:AddColorPicker({
                    Flag = config.Flag,
                    Default = config.Default,
                    Callback = config.Callback,
                    Transparency = config.Transparency or 0,
                })
            end)
        end
    end
end
local function buildLibraryUI(lib)
    local window = lib.new({
        Name = "Op1NIGGAs",
        Keybind = "RightShift",
        Logo = "rbxassetid://120245531583106",
        Scale = lib.Scale.Window,
        TextSize = 15,
    })

    window:DrawCategory({ Name = "Combat" })
    local combatTab = window:DrawTab({ Name = "Combat", Icon = "crosshair", Type = "Double" })
    local aimbotSection = combatTab:DrawSection({ Name = "Aimbot", Position = "left" })
    local weaponSection = combatTab:DrawSection({ Name = "Weapon", Position = "right" })

    aimbotSection:AddToggle({ Name = "Silent Aim Enabled", Flag = "silent_aim_enabled", Default = false, Callback = setSilentAim })
    aimbotSection:AddSlider({ Name = "Silent Aim FOV", Flag = "silent_aim_fov", Default = 60, Min = 10, Max = 400, Round = 0, Callback = setSilentAimFov })
    aimbotSection:AddSlider({ Name = "Silent Smoothness", Flag = "silent_aim_smoothness", Default = 1, Min = 0.01, Max = 1, Round = 2, Callback = setSilentAimSmoothness })
    aimbotSection:AddToggle({ Name = "Target Players", Flag = "silent_target_players", Default = false, Callback = function(v) setSilentAimTargets(v, nil, nil) end })
    aimbotSection:AddToggle({ Name = "Target Gadgets", Flag = "silent_target_gadgets", Default = false, Callback = function(v) setSilentAimTargets(nil, v, nil) end })
    aimbotSection:AddToggle({ Name = "Target Cameras", Flag = "silent_target_cameras", Default = false, Callback = function(v) setSilentAimTargets(nil, nil, v) end })

    weaponSection:AddToggle({ Name = "Gun Mod Enabled", Flag = "gun_mod_enabled", Default = false, Callback = setGunModEnabled })
    weaponSection:AddSlider({ Name = "Recoil Reduction", Flag = "gun_mod_recoil", Default = 0, Min = 0, Max = 1, Round = 2, Callback = function(v) setGunModConfig("recoil_reduction", v) end })
    weaponSection:AddSlider({ Name = "Horizontal Recoil", Flag = "gun_mod_hrecoil", Default = 0, Min = 0, Max = 1, Round = 2, Callback = function(v) setGunModConfig("horizontal_recoil", v) end })
    weaponSection:AddToggle({ Name = "No Spread", Flag = "gun_mod_spread", Default = false, Callback = function(v) setGunModConfig("no_spread", v) end })
    weaponSection:AddSlider({ Name = "Fire Rate", Flag = "gun_mod_firerate", Default = 1200, Min = 50, Max = 2000, Round = 0, Callback = function(v) setGunModConfig("custom_firerate", v) end })
    weaponSection:AddSlider({ Name = "Reload Speed", Flag = "gun_mod_reload", Default = 0.1, Min = 0.05, Max = 1, Round = 2, Callback = function(v) setGunModConfig("reload_speed", v) end })
    weaponSection:AddToggle({ Name = "Force Auto", Flag = "gun_mod_forceauto", Default = false, Callback = function(v) setGunModConfig("force_auto", v) end })
    weaponSection:AddToggle({ Name = "Instant ADS", Flag = "gun_mod_ads", Default = false, Callback = function(v) setGunModConfig("instant_ads", v) end })
    weaponSection:AddSlider({ Name = "Zoom", Flag = "gun_mod_zoom", Default = 1.5, Min = 1, Max = 4, Round = 2, Callback = function(v) setGunModConfig("custom_zoom", v) end })

    window:DrawCategory({ Name = "Visuals" })
    local visualsTab = window:DrawTab({ Name = "Visuals", Icon = "eye", Type = "Double" })
    local espSection = visualsTab:DrawSection({ Name = "ESP", Position = "left" })
    local lightingSection = visualsTab:DrawSection({ Name = "Lighting", Position = "right" })

    espSection:AddToggle({ Name = "ESP Enabled", Flag = "esp_enabled", Default = false, Callback = setEspEnabled })
    espSection:AddToggle({ Name = "ESP Team Check", Flag = "esp_team_check", Default = false, Callback = setEspTeamCheck })
    espSection:AddToggle({ Name = "Player ESP", Flag = "esp_players", Default = false, Callback = setEspPlayers })
    espSection:AddToggle({ Name = "Gadget ESP", Flag = "esp_objects", Default = false, Callback = setEspObjects })
    espSection:AddToggle({ Name = "Hitbox Enabled", Flag = "hitbox_enabled", Default = false, Callback = setHitboxEnabled })
    espSection:AddSlider({ Name = "Hitbox Size", Flag = "hitbox_size", Default = 5, Min = 1, Max = 10, Round = 1, Callback = setHitboxSize })
    espSection:AddSlider({ Name = "Hitbox Transparency", Flag = "hitbox_transparency", Default = 0.9, Min = 0, Max = 1, Round = 2, Callback = setHitboxTransparency })

    addColorPickerSafe(espSection, { Name = "Player ESP", Flag = "esp_player_color", Default = Color3.fromRGB(210, 50, 80), Callback = setEspPlayerColor })
    addColorPickerSafe(espSection, { Name = "Gadget ESP", Flag = "esp_object_color", Default = Color3.fromRGB(0, 255, 255), Callback = setEspObjectColor })
    addColorPickerSafe(espSection, { Name = "Drone", Flag = "esp_drone_color", Default = Color3.fromRGB(0, 255, 255), Callback = setEspDroneColor })
    addColorPickerSafe(espSection, { Name = "Claymore", Flag = "esp_claymore_color", Default = Color3.fromRGB(255, 0, 0), Callback = setEspClaymoreColor })
    addColorPickerSafe(espSection, { Name = "Proximity Alarm", Flag = "esp_proximity_alarm_color", Default = Color3.fromRGB(255, 165, 0), Callback = setEspProximityAlarmColor })
    addColorPickerSafe(espSection, { Name = "Sticky Camera", Flag = "esp_sticky_camera_color", Default = Color3.fromRGB(255, 192, 203), Callback = setEspStickyCameraColor })
    addColorPickerSafe(espSection, { Name = "Hitbox Color", Flag = "hitbox_color", Default = Color3.fromRGB(255, 0, 0), Callback = setHitboxColor })

    lightingSection:AddToggle({ Name = "Fullbright", Flag = "fullbright_enabled", Default = false, Callback = setFullbright })
    lightingSection:AddSlider({ Name = "FB Brightness", Flag = "fb_brightness", Default = 1, Min = 0, Max = 5, Round = 2, Callback = function(v) setFullbrightSetting("Brightness", v) end })
    lightingSection:AddSlider({ Name = "FB ClockTime", Flag = "fb_clocktime", Default = 12, Min = 0, Max = 24, Round = 1, Callback = function(v) setFullbrightSetting("ClockTime", v) end })
    lightingSection:AddSlider({ Name = "FB FogEnd", Flag = "fb_fogend", Default = 786543, Min = 1000, Max = 1000000, Round = 0, Callback = function(v) setFullbrightSetting("FogEnd", v) end })
    lightingSection:AddToggle({ Name = "FB GlobalShadows", Flag = "fb_shadows", Default = false, Callback = function(v) setFullbrightSetting("GlobalShadows", v) end })
    addColorPickerSafe(lightingSection, { Name = "FB Ambient", Flag = "fb_ambient", Default = Color3.fromRGB(178, 178, 178), Callback = function(c) setFullbrightSetting("Ambient", c) end })

    window:DrawCategory({ Name = "Config" })
    local configManager = lib:ConfigManager({ Directory = "Compkiller-UI", Config = "OP1-Loader" })
    local configTab = window:DrawConfig({ Name = "Config", Icon = "folder", Config = configManager })
    configTab:Init()

    log("Library UI initialized")
end

local function buildFallbackUI()
    local CoreGui = game:GetService("CoreGui")
    local UserInputService = game:GetService("UserInputService")

    local gui = Instance.new("ScreenGui")
    gui.Name = "OP1_Fallback_UI"
    gui.ResetOnSpawn = false
    gui.Parent = CoreGui

    local frame = Instance.new("Frame")
    frame.Size = UDim2.fromOffset(300, 220)
    frame.Position = UDim2.fromScale(0.03, 0.2)
    frame.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    frame.BorderSizePixel = 0
    frame.Parent = gui

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, -12, 0, 28)
    title.Position = UDim2.fromOffset(8, 6)
    title.BackgroundTransparency = 1
    title.Font = Enum.Font.GothamBold
    title.TextSize = 15
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.Text = "OP1 Fallback"
    title.Parent = frame

    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 6)
    list.Parent = frame

    local pad = Instance.new("UIPadding")
    pad.PaddingTop = UDim.new(0, 40)
    pad.PaddingLeft = UDim.new(0, 10)
    pad.PaddingRight = UDim.new(0, 10)
    pad.PaddingBottom = UDim.new(0, 10)
    pad.Parent = frame

    local function makeBtn(text, fn)
        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 0, 30)
        btn.Text = text
        btn.Font = Enum.Font.GothamSemibold
        btn.TextSize = 13
        btn.TextColor3 = Color3.fromRGB(235, 235, 235)
        btn.BackgroundColor3 = Color3.fromRGB(40, 40, 46)
        btn.Parent = frame
        btn.MouseButton1Click:Connect(fn)
    end

    makeBtn("Silent Aim ON", function() setSilentAim(true) end)
    makeBtn("Silent Aim OFF", function() setSilentAim(false) end)
    makeBtn("ESP ON", function() setEspEnabled(true) end)
    makeBtn("ESP OFF", function() setEspEnabled(false) end)
    makeBtn("Fullbright ON", function() setFullbright(true) end)
    makeBtn("Fullbright OFF", function() setFullbright(false) end)

    UserInputService.InputBegan:Connect(function(input, gpe)
        if not gpe and input.KeyCode == Enum.KeyCode.RightShift then
            frame.Visible = not frame.Visible
        end
    end)
end

local lib = loadUiLibrary()
if lib then
    local ok, err = pcall(buildLibraryUI, lib)
    if not ok then
        log("Library UI build failed -> " .. tostring(err))
        buildFallbackUI()
    end
else
    buildFallbackUI()
end
