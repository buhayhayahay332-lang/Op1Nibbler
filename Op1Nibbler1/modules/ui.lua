return function(ctx, Modules)
    local repo = "https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/"

    local okLibrary, Library = pcall(function()
        return loadstring(game:HttpGet(repo .. "Library.lua"))()
    end)

    if not okLibrary then
        warn("[Op1Nibbler] Linoria load failed:", Library)
        return
    end

    local okTheme, ThemeManager = pcall(function()
        return loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
    end)

    local okSave, SaveManager = pcall(function()
        return loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
    end)

    local Window = Library:CreateWindow({
        Title = "Op1Nibbler - Modular",
        Center = true,
        AutoShow = true
    })

    local Tabs = {
        Combat = Window:AddTab("Combat"),
        Visuals = Window:AddTab("Visuals"),
        World = Window:AddTab("World"),
        UI = Window:AddTab("UI Settings")
    }

    local Gun = Tabs.Combat:AddLeftGroupbox("Gun Mods")
    Gun:AddToggle("gm_en", { Text = "Enable Gun Mods", Default = Modules.GunMods.enabled }):OnChanged(function(v) Modules.GunMods:SetEnabled(v) end)
    Gun:AddSlider("gm_recoil", { Text = "Recoil Mult", Default = Modules.GunMods.recoilReduction, Min = 0, Max = 1, Rounding = 2 }):OnChanged(function(v) Modules.GunMods:SetRecoilReduction(v) end)
    Gun:AddSlider("gm_hrecoil", { Text = "Horizontal Recoil", Default = Modules.GunMods.horizontalRecoil, Min = -2, Max = 2, Rounding = 2 }):OnChanged(function(v) Modules.GunMods:SetHorizontalRecoil(v) end)
    Gun:AddToggle("gm_nospread", { Text = "No Spread", Default = Modules.GunMods.noSpread }):OnChanged(function(v) Modules.GunMods:SetNoSpread(v) end)
    Gun:AddSlider("gm_acc", { Text = "Accuracy", Default = Modules.GunMods.accuracyMultiplier, Min = 0, Max = 2, Rounding = 2 }):OnChanged(function(v) Modules.GunMods:SetAccuracyMultiplier(v) end)
    Gun:AddSlider("gm_rate", { Text = "Firerate", Default = Modules.GunMods.customFirerate, Min = 100, Max = 3000, Rounding = 0 }):OnChanged(function(v) Modules.GunMods:SetCustomFirerate(v) end)
    Gun:AddSlider("gm_reload", { Text = "Reload", Default = Modules.GunMods.reloadSpeed, Min = 0.05, Max = 2, Rounding = 2 }):OnChanged(function(v) Modules.GunMods:SetReloadSpeed(v) end)
    Gun:AddToggle("gm_auto", { Text = "Force Auto", Default = Modules.GunMods.forceAuto }):OnChanged(function(v) Modules.GunMods:SetForceAuto(v) end)
    Gun:AddToggle("gm_ads", { Text = "Instant ADS", Default = Modules.GunMods.instantADS }):OnChanged(function(v) Modules.GunMods:SetInstantADS(v) end)
    Gun:AddSlider("gm_zoom", { Text = "Zoom", Default = Modules.GunMods.customZoom, Min = 1, Max = 5, Rounding = 2 }):OnChanged(function(v) Modules.GunMods:SetCustomZoom(v) end)

    local SA = Tabs.Combat:AddRightGroupbox("Silent Aim")
    SA:AddToggle("sa_en", { Text = "Enable Silent Aim", Default = Modules.SilentAim.enabled }):OnChanged(function(v) Modules.SilentAim:SetEnabled(v) end)
    SA:AddSlider("sa_fov", { Text = "FOV", Default = Modules.SilentAim.fov, Min = 20, Max = 400, Rounding = 0 }):OnChanged(function(v) Modules.SilentAim:SetFov(v) end)
    SA:AddSlider("sa_smooth", { Text = "Smoothness", Default = Modules.SilentAim.smoothness, Min = 0.05, Max = 1, Rounding = 2 }):OnChanged(function(v) Modules.SilentAim:SetSmoothness(v) end)
    SA:AddToggle("sa_p", { Text = "Target Players", Default = Modules.SilentAim.targetPlayers }):OnChanged(function(v) Modules.SilentAim:SetTargetPlayers(v) end)
    SA:AddToggle("sa_g", { Text = "Target Gadgets", Default = Modules.SilentAim.targetGadgets }):OnChanged(function(v) Modules.SilentAim:SetTargetGadgets(v) end)
    SA:AddToggle("sa_c", { Text = "Target Cameras", Default = Modules.SilentAim.targetCameras }):OnChanged(function(v) Modules.SilentAim:SetTargetCameras(v) end)

    local HB = Tabs.Combat:AddRightGroupbox("Hitbox")
    HB:AddToggle("hb_en", { Text = "Enable Hitbox", Default = Modules.Hitbox.enabled }):OnChanged(function(v) Modules.Hitbox:SetEnabled(v) end)
    HB:AddToggle("hb_team", { Text = "Team Check", Default = Modules.Hitbox.teamCheck }):OnChanged(function(v) Modules.Hitbox.teamCheck = v end)
    HB:AddSlider("hb_size", { Text = "Size", Default = Modules.Hitbox.size, Min = 2, Max = 12, Rounding = 1 }):OnChanged(function(v) Modules.Hitbox:SetSize(v) end)
    HB:AddSlider("hb_t", { Text = "Transparency", Default = Modules.Hitbox.transparency, Min = 0, Max = 1, Rounding = 2 }):OnChanged(function(v) Modules.Hitbox:SetTransparency(v) end)
    HB:AddLabel("Hitbox Color"):AddColorPicker("hb_color", {
        Default = Modules.Hitbox.color,
        Title = "Hitbox Color",
        Callback = function(v)
            Modules.Hitbox:SetColor(v)
        end
    })

    local ESP = Tabs.Visuals:AddLeftGroupbox("ESP")
    ESP:AddToggle("esp_en", { Text = "Enable ESP", Default = Modules.ESP.enabled }):OnChanged(function(v) Modules.ESP:SetEnabled(v) end)
    ESP:AddToggle("esp_team", { Text = "Team Check", Default = Modules.ESP.teamCheck }):OnChanged(function(v) Modules.ESP:SetTeamCheck(v) end)
    ESP:AddToggle("esp_player", { Text = "Player Boxes", Default = Modules.ESP.playerBoxEnabled }):OnChanged(function(v) Modules.ESP:SetPlayerBoxEnabled(v) end)
    ESP:AddToggle("esp_object", { Text = "Object Boxes", Default = Modules.ESP.objectBoxEnabled }):OnChanged(function(v) Modules.ESP:SetObjectBoxEnabled(v) end)
    ESP:AddSlider("esp_pt", { Text = "Player Thickness", Default = Modules.ESP.playerThickness, Min = 1, Max = 5, Rounding = 1 }):OnChanged(function(v) Modules.ESP:SetPlayerThickness(v) end)
    ESP:AddSlider("esp_ot", { Text = "Object Thickness", Default = Modules.ESP.objectThickness, Min = 1, Max = 5, Rounding = 1 }):OnChanged(function(v) Modules.ESP:SetObjectThickness(v) end)

    local ESPColors = Tabs.Visuals:AddRightGroupbox("ESP Colors")
    ESPColors:AddLabel("Players"):AddColorPicker("esp_pc", {
        Default = Modules.ESP.playerColor,
        Title = "Player",
        Callback = function(v)
            Modules.ESP:SetPlayerColor(v)
        end
    })
    ESPColors:AddLabel("Drone"):AddColorPicker("esp_dc", {
        Default = Modules.ESP.droneColor,
        Title = "Drone",
        Callback = function(v)
            Modules.ESP:SetDroneColor(v)
        end
    })
    ESPColors:AddLabel("Claymore"):AddColorPicker("esp_cc", {
        Default = Modules.ESP.claymoreColor,
        Title = "Claymore",
        Callback = function(v)
            Modules.ESP:SetClaymoreColor(v)
        end
    })
    ESPColors:AddLabel("Proximity"):AddColorPicker("esp_prc", {
        Default = Modules.ESP.proximityColor,
        Title = "Proximity",
        Callback = function(v)
            Modules.ESP:SetProximityColor(v)
        end
    })
    ESPColors:AddLabel("Sticky"):AddColorPicker("esp_sc", {
        Default = Modules.ESP.stickyColor,
        Title = "Sticky Camera",
        Callback = function(v)
            Modules.ESP:SetStickyColor(v)
        end
    })

    local WR = Tabs.World:AddLeftGroupbox("World")
    WR:AddToggle("fb_en", { Text = "Fullbright", Default = Modules.Fullbright.enabled }):OnChanged(function(v) Modules.Fullbright:SetEnabled(v) end)

    local UIG = Tabs.UI:AddLeftGroupbox("Menu")
    UIG:AddLabel("Menu Keybind"):AddKeyPicker("MenuKeybind", { Default = "RightControl", NoUI = true, Text = "Menu Keybind" })

    if okTheme then
        ThemeManager:SetLibrary(Library)
        ThemeManager:ApplyToTab(Tabs.UI)
    end

    if okSave then
        SaveManager:SetLibrary(Library)
        SaveManager:IgnoreThemeSettings()
        SaveManager:SetIgnoreIndexes({ "MenuKeybind" })
        SaveManager:SetFolder("Op1Nibbler")
        SaveManager:BuildConfigSection(Tabs.UI)
    end

    Library.ToggleKeybind = Options.MenuKeybind
end

