local CONFIG = {
    recoil_reduction = 0,
    horizontal_recoil = 0,
    no_spread = false,
    accuracy_multiplier = 1,
    custom_firerate = 1200,
    reload_speed = 0.1,
    force_auto = false,
    instant_ads = false,
    custom_zoom = 1.5,
}

local cloneref = cloneref or function(obj) return obj end
local clonefunction = clonefunction or function(fn) return fn end
local newcclosure = newcclosure or function(fn) return fn end

local pcall = clonefunction(pcall)
local setmetatable = clonefunction(setmetatable)
local typeof = clonefunction(typeof)
local rawget = clonefunction(rawget)

local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))

local Module = {
    _initialized = false,
    _enabled = false,
    _hooked = false,
    _gunModule = nil,
    _originalAutomatic = nil,
    config = CONFIG,
}

local GunModule

local original_recoil_function
local original_send_shoot
local original_input_render
local original_reload_begin
local original_sights
local original_update_sight_lens

local recoil_up_get
local recoil_side_get
local spread_get
local firerate_get
local reload_speed_get
local ads_get
local zoom_get
local perfect_accuracy = { Value = CONFIG.accuracy_multiplier }

local recoil_proxy_mt
local spread_firerate_proxy_mt
local firerate_proxy_mt
local reload_proxy_mt
local sights_proxy_mt

local function cloneCallable(ref)
    if type(ref) ~= "function" then
        return ref
    end

    local ok, cloned = pcall(clonefunction, ref)
    if ok and cloned then
        return cloned
    end

    return ref
end

local function setAutomaticValue(target, value)
    if target == nil then
        return nil
    end

    if type(target) == "boolean" then
        return value
    end

    if type(target) == "table" then
        if type(target.set) == "function" then
            pcall(function() target:set(value) end)
        end
        if target.Value ~= nil then
            pcall(function() target.Value = value end)
        end
        return nil
    end

    return nil
end

function Module:_applyForceAuto(value)
    if not GunModule then
        return
    end

    if GunModule.automatic ~= nil then
        local replacement = setAutomaticValue(GunModule.automatic, value)
        if replacement ~= nil then
            GunModule.automatic = replacement
        else
            pcall(function()
                GunModule.automatic = value
            end)
        end
    end
end

function Module:_buildLegacyCachedFunctions()
    recoil_up_get = newcclosure(function(original_state)
        local val = original_state:get()
        return (typeof(val) == "number" and val * CONFIG.recoil_reduction) or 0
    end)

    recoil_side_get = newcclosure(function()
        return CONFIG.horizontal_recoil
    end)

    spread_get = newcclosure(function()
        return CONFIG.no_spread and 0 or 1
    end)

    firerate_get = newcclosure(function()
        return CONFIG.custom_firerate
    end)

    reload_speed_get = newcclosure(function()
        return CONFIG.reload_speed
    end)

    ads_get = newcclosure(function()
        return CONFIG.instant_ads and 0.01 or 0.3
    end)

    zoom_get = newcclosure(function()
        return CONFIG.custom_zoom
    end)

    recoil_proxy_mt = {
        __index = newcclosure(function(t, key)
            local real_states = rawget(t, "__real_states")
            if not real_states then return nil end

            local state = real_states[key]
            if typeof(state) == "table" and state.get then
                if key == "recoil_up" then
                    return { get = function() return recoil_up_get(state) end }
                elseif key == "recoil_side" then
                    return { get = recoil_side_get }
                end
            end
            return state
        end),
        __metatable = "locked",
    }

    spread_firerate_proxy_mt = {
        __index = newcclosure(function(t, key)
            local real_states = rawget(t, "__real_states")
            if not real_states then return nil end

            local state = real_states[key]
            if typeof(state) == "table" and state.get then
                if key == "spread" then
                    return { get = spread_get }
                elseif key == "firerate" then
                    return { get = firerate_get }
                end
            end
            return state
        end),
        __metatable = "locked",
    }

    firerate_proxy_mt = {
        __index = newcclosure(function(t, key)
            local real_states = rawget(t, "__real_states")
            if not real_states then return nil end

            local state = real_states[key]
            if typeof(state) == "table" and state.get and key == "firerate" then
                return { get = firerate_get }
            end
            return state
        end),
        __metatable = "locked",
    }

    reload_proxy_mt = {
        __index = newcclosure(function(t, key)
            local real_states = rawget(t, "__real_states")
            if not real_states then return nil end

            local state = real_states[key]
            if typeof(state) == "table" and state.get and key == "reload_speed" then
                return { get = reload_speed_get }
            end
            return state
        end),
        __metatable = "locked",
    }

    sights_proxy_mt = {
        __index = newcclosure(function(t, key)
            local real_states = rawget(t, "__real_states")
            if not real_states then return nil end

            local state = real_states[key]
            if typeof(state) == "table" and state.get then
                if key == "ads" then
                    return { get = ads_get }
                elseif key == "zoom" then
                    return { get = zoom_get }
                end
            end
            return state
        end),
        __metatable = "locked",
    }
end

function Module:_installHooks(force)
    if self._hooked and not force then
        return true
    end

    local okRequire, gunModuleOrErr = pcall(function()
        return require(ReplicatedStorage.Modules.Items.Item.Gun)
    end)
    if not okRequire or type(gunModuleOrErr) ~= "table" then
        return false, "gun module require failed: " .. tostring(gunModuleOrErr)
    end

    GunModule = gunModuleOrErr
    self._gunModule = GunModule

    original_recoil_function = cloneCallable(GunModule.recoil_function)
    original_send_shoot = cloneCallable(GunModule.send_shoot)
    original_input_render = cloneCallable(GunModule.input_render)
    original_reload_begin = cloneCallable(GunModule.reload_begin)
    original_sights = cloneCallable(GunModule.sights)
    original_update_sight_lens = cloneCallable(GunModule.update_sight_lens)
    self._originalAutomatic = GunModule.automatic

    self:_buildLegacyCachedFunctions()

    GunModule.recoil_function = newcclosure(function(selfGun, owner)
        if not Module._enabled or not selfGun or not selfGun.states then
            return original_recoil_function(selfGun, owner)
        end

        local real_states = selfGun.states
        local proxy_states = { __real_states = real_states }
        setmetatable(proxy_states, recoil_proxy_mt)

        selfGun.states = proxy_states

        local success, err = pcall(original_recoil_function, selfGun, owner)

        selfGun.states = real_states

        if not success then
            warn("Recoil error:", err)
        end
    end)

    GunModule.send_shoot = newcclosure(function(selfGun)
        if not Module._enabled or not selfGun or not selfGun.states then
            return original_send_shoot(selfGun)
        end

        local real_states = selfGun.states
        local real_accuracy = selfGun.accuracy

        local proxy_states = { __real_states = real_states }
        setmetatable(proxy_states, spread_firerate_proxy_mt)

        selfGun.states = proxy_states
        selfGun.accuracy = perfect_accuracy

        local success, err = pcall(original_send_shoot, selfGun)

        selfGun.states = real_states
        selfGun.accuracy = real_accuracy

        if not success then
            warn("Shoot error:", err)
        end
    end)

    GunModule.input_render = newcclosure(function(selfGun, ...)
        if not Module._enabled or not selfGun or not selfGun.states then
            return original_input_render(selfGun, ...)
        end

        local real_states = selfGun.states

        local proxy_states = { __real_states = real_states }
        setmetatable(proxy_states, firerate_proxy_mt)

        selfGun.states = proxy_states

        local success, err = pcall(original_input_render, selfGun, ...)

        selfGun.states = real_states

        if not success then
            warn("Render error:", err)
        end
    end)

    GunModule.reload_begin = newcclosure(function(selfGun, ...)
        if not Module._enabled or not selfGun or not selfGun.states then
            return original_reload_begin(selfGun, ...)
        end

        local real_states = selfGun.states

        local proxy_states = { __real_states = real_states }
        setmetatable(proxy_states, reload_proxy_mt)

        selfGun.states = proxy_states

        local success, err = pcall(original_reload_begin, selfGun, ...)

        selfGun.states = real_states

        if not success then
            warn("Reload error:", err)
        end
    end)

    GunModule.sights = newcclosure(function(selfGun, ...)
        if not Module._enabled or not selfGun or not selfGun.states then
            return original_sights(selfGun, ...)
        end

        local real_states = selfGun.states

        local proxy_states = { __real_states = real_states }
        setmetatable(proxy_states, sights_proxy_mt)

        selfGun.states = proxy_states

        local success, err = pcall(original_sights, selfGun, ...)

        selfGun.states = real_states

        if not success then
            warn("Sights error:", err)
        end
    end)

    GunModule.update_sight_lens = newcclosure(function(selfGun, ...)
        if not Module._enabled or not selfGun or not selfGun.states then
            return original_update_sight_lens(selfGun, ...)
        end

        local real_states = selfGun.states

        local proxy_states = { __real_states = real_states }
        setmetatable(proxy_states, sights_proxy_mt)

        selfGun.states = proxy_states

        local success, err = pcall(original_update_sight_lens, selfGun, ...)

        selfGun.states = real_states

        if not success then
            warn("Update sight lens error:", err)
        end
    end)

    self._hooked = true
    return true
end

function Module:init(force)
    if self._initialized and not force then
        return true
    end

    local okInstall, installErr = self:_installHooks(force == true)
    if not okInstall then
        return false, installErr
    end

    self._initialized = true

    if self._enabled and CONFIG.force_auto then
        self:_applyForceAuto(true)
    elseif self._originalAutomatic ~= nil then
        self:_applyForceAuto(self._originalAutomatic)
    end

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

    if self._enabled and CONFIG.force_auto then
        self:_applyForceAuto(true)
    elseif self._originalAutomatic ~= nil then
        self:_applyForceAuto(self._originalAutomatic)
    end

    return true
end

function Module:updateConfig(newConfig)
    if type(newConfig) ~= "table" then
        return false, "config must be table"
    end

    for key, value in pairs(newConfig) do
        if CONFIG[key] ~= nil then
            CONFIG[key] = value
        end
    end

    perfect_accuracy.Value = CONFIG.accuracy_multiplier

    if self._initialized and GunModule then
        if self._enabled and CONFIG.force_auto then
            self:_applyForceAuto(true)
        elseif self._originalAutomatic ~= nil then
            self:_applyForceAuto(self._originalAutomatic)
        end
    end

    return true
end

function Module:getConfig()
    return CONFIG
end

function Module:unload()
    if not self._hooked or not GunModule then
        self._initialized = false
        self._enabled = false
        return true
    end

    if original_recoil_function then GunModule.recoil_function = original_recoil_function end
    if original_send_shoot then GunModule.send_shoot = original_send_shoot end
    if original_input_render then GunModule.input_render = original_input_render end
    if original_reload_begin then GunModule.reload_begin = original_reload_begin end
    if original_sights then GunModule.sights = original_sights end
    if original_update_sight_lens then GunModule.update_sight_lens = original_update_sight_lens end

    if self._originalAutomatic ~= nil then
        self:_applyForceAuto(self._originalAutomatic)
    end

    self._initialized = false
    self._enabled = false
    self._hooked = false
    return true
end

return Module
