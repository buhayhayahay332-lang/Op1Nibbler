if getgenv().__OP1NIBBLER_UI__ then
    return
end
getgenv().__OP1NIBBLER_UI__ = true

local cloneref = cloneref or function(v)
    return v
end

local function import(path)
    local baseUrl = getgenv().OP1NIBBLER_BASE_URL or
                        "https://raw.githubusercontent.com/buhayhayahay332-lang/Op1Nibbler/main/Op1Nibbler1/"

    if game.HttpGet and baseUrl and #baseUrl > 0 then
        local url = baseUrl .. path
        local okHttp, source = pcall(function()
            return game:HttpGet(url)
        end)

        if okHttp and source and #source > 0 and loadstring then
            local chunk = loadstring(source, "@" .. url)
            if chunk then
                return chunk()
            end
        end
    end

    if loadfile then
        local ok, chunk = pcall(loadfile, path)
        if ok and chunk then
            return chunk()
        end
    end

    if readfile and loadstring then
        local ok, source = pcall(readfile, path)
        if ok and source then
            local chunk = loadstring(source, "@" .. path)
            return chunk()
        end
    end

    error("[Op1Nibbler] Failed to import: " .. path)
end

local Services = {
    Lighting = cloneref(game:GetService("Lighting")),
    Workspace = cloneref(game:GetService("Workspace")),
    RunService = cloneref(game:GetService("RunService")),
    UserInputService = cloneref(game:GetService("UserInputService")),
    ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
}

local function safeRequire(pathFn)
    local ok, result = pcall(pathFn)
    if ok then
        return result
    end
    warn("[Op1Nibbler] require failed:", result)
    return nil
end

local GunModule = safeRequire(function()
    return require(Services.ReplicatedStorage.Modules.Items.Item.Gun)
end)

local ctx = {
    Services = Services,
    GunModule = GunModule
}

local Modules = {
    Fullbright = import("modules/fullbright.lua")(ctx),
    Hitbox = import("modules/hitbox.lua")(ctx),
    SilentAim = import("modules/silent_aim.lua")(ctx),
    GunMods = import("modules/gun_mods.lua")(ctx),
    ESP = import("modules/esp.lua")(ctx)
}

Modules.SilentAim:Init()
Modules.GunMods:Init()
Modules.ESP:Init()

import("modules/ui.lua")(ctx, Modules)

getgenv().Op1NibblerModules = Modules
