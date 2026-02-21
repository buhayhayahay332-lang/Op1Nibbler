if getgenv().__OP1NIBBLER_UI__ then
    return
end
getgenv().__OP1NIBBLER_UI__ = true

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

local Runtime = {
    cloneref = cloneref or function(v)
        return v
    end,
    clonefunction = clonefunction or clonefunc or function(v)
        return v
    end,
    newcclosure = newcclosure or function(fn)
        return fn
    end,
    hookfunction = hookfunction or function(f)
        return f
    end,
    hookmetamethod = hookmetamethod,
    replaceclosure = replaceclosure or function()
    end,
    getrawmetatable = getrawmetatable or function()
        return {}
    end,
    setreadonly = setreadonly or function()
    end
}
Runtime.InstanceNew = Instance.new

local Services = {
    Lighting = Runtime.cloneref(game:GetService("Lighting")),
    Workspace = Runtime.cloneref(game:GetService("Workspace")),
    RunService = Runtime.cloneref(game:GetService("RunService")),
    UserInputService = Runtime.cloneref(game:GetService("UserInputService")),
    ReplicatedStorage = Runtime.cloneref(game:GetService("ReplicatedStorage")),
    Players = Runtime.cloneref(game:GetService("Players"))
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
    Runtime = Runtime,
    GunModule = GunModule
}

local Modules = {
    Fullbright = import("modules/fullbright.lua")(ctx),
    Hitbox = import("modules/hitbox.lua")(ctx),
    SilentAim = import("modules/silent_aim.lua")(ctx),
    GunMods = import("modules/gun_mods.lua")(ctx),
    ESP = import("modules/esp.lua")(ctx),
    NoSmokeFlash = import("modules/no_smoke_flash.lua")(ctx)
}

Modules.SilentAim:Init()
Modules.GunMods:Init()
Modules.ESP:Init()
Modules.NoSmokeFlash:Init()

import("modules/ui.lua")(ctx, Modules)

getgenv().Op1NibblerModules = Modules
