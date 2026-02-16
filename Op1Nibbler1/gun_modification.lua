local cloneref = cloneref or function(obj) return obj end
local clonefunction = clonefunction or function(fn) return fn end
local newcclosure = newcclosure or function(fn) return fn end

local pcall_safe = clonefunction(pcall)
local setmetatable_safe = clonefunction(setmetatable)
local typeof_safe = clonefunction(typeof)
local rawget_safe = clonefunction(rawget)

local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))

local Module = {
    _initialized = false,
    _enabled = false,
    _gunModule = nil,
    _original = {},
    _originalAutomatic = nil,
    config = {
        recoil_reduction = 0,
        horizontal_recoil = 0,
        no_spread = false,
        accuracy_multiplier = 1,
        custom_firerate = 1200,
        reload_speed = 0.1,
        force_auto = false,
        instant_ads = false,
        custom_zoom = 1.5,
    },
}

local recoil_proxy_mt
local spread_firerate_proxy_mt
local firerate_proxy_mt
local reload_proxy_mt
local sights_proxy_mt
local perfect_accuracy = { Value = Module.config.accuracy_multiplier }

local function cloneCallable(ref)
    if type(ref) ~= "function" then
        return ref
    end

    local ok, cloned = pcall_safe(clonefunction, ref)
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
            pcall_safe(function() target:set(value) end)
        end
        if target.Value ~= nil then
            pcall_safe(function() target.Value = value end)
        end
        return nil
    end

    return nil
end

function Module:_applyForceAuto(value)
    if not self._gunModule then
        return
    end

    if self._gunModule.automatic ~= nil then
        local replacement = setAutomaticValue(self._gunModule.automatic, value)
        if replacement ~= nil then
            self._gunModule.automatic = replacement
        else
            pcall_safe(function()
                self._gunModule.automatic = value
            end)
        end
    end
end

function Module:_buildLegacyProxies()
    local recoil_up_get = newcclosure(function(original_state)
        local val = original_state:get()
        return (typeof_safe(val) == "number" and val * self.config.recoil_reduction) or 0
    end)

    local recoil_side_get = newcclosure(function()
        return self.config.horizontal_recoil
    end)

    local spread_get = newcclosure(function()
        return self.config.no_spread and 0 or 1
    end)

    local firerate_get = newcclosure(function()
        return self.config.custom_firerate
    end)

    local reload_speed_get = newcclosure(function()
        return self.config.reload_speed
    end)

    local ads_get = newcclosure(function()
        return self.config.instant_ads and 0.01 or 0.3
    end)

    local zoom_get = newcclosure(function()
        return self.config.custom_zoom
    end)

    recoil_proxy_mt = {
        __index = newcclosure(function(t, key)
            local real_states = rawget_safe(t, "__real_states")
            if not real_states then return nil end

            local state = real_states[key]
            if typeof_safe(state) == "table" and state.get then
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
            local real_states = rawget_safe(t, "__real_states")
            if not real_states then return nil end

            local state = real_states[key]
            if typeof_safe(state) == "table" and state.get then
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
            local real_states = rawget_safe(t, "__real_states")
            if not real_states then return nil end

            local state = real_states[key]
            if typeof_safe(state) == "table" and state.get and key == "firerate" then
                return { get = firerate_get }
            end

            return state
        end),
        __metatable = "locked",
    }

    reload_proxy_mt = {
        __index = newcclosure(function(t, key)
            local real_states = rawget_safe(t, "__real_states")
            if not real_states then return nil end

            local state = real_states[key]
            if typeof_safe(state) == "table" and state.get and key == "reload_speed" then
                return { get = reload_speed_get }
            end

            return state
        end),
        __metatable = "locked",
    }

    sights_proxy_mt = {
        __index = newcclosure(function(t, key)
            local real_states = rawget_safe(t, "__real_states")
            if not real_states then return nil end

            local state = real_states[key]
            if typeof_safe(state) == "table" and state.get then
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

function Module:_installHooks()
    local okRequire, gunModuleOrErr = pcall_safe(function()
        return require(ReplicatedStorage.Modules.Items.Item.Gun)
    end)
    if not okRequire or type(gunModuleOrErr) ~= "table" then
        return false, "gun module require failed: " .. tostring(gunModuleOrErr)
    end

    self._gunModule = gunModuleOrErr
    self._original.recoil_function = cloneCallable(self._gunModule.recoil_function)
    self._original.send_shoot = cloneCallable(self._gunModule.send_shoot)
    self._original.input_render = cloneCallable(self._gunModule.input_render)
    self._original.reload_begin = cloneCallable(self._gunModule.reload_begin)
    self._original.sights = cloneCallable(self._gunModule.sights)
    self._original.update_sight_lens = cloneCallable(self._gunModule.update_sight_lens)
    self._originalAutomatic = self._gunModule.automatic

    self:_buildLegacyProxies()

    self._gunModule.recoil_function = newcclosure(function(gun, owner)
        if not self._enabled then
            return self._original.recoil_function(gun, owner)
        end
        if not gun or not gun.states then
            return self._original.recoil_function(gun, owner)
        end

        local real_states = gun.states
        local proxy_states = { __real_states = real_states }
        setmetatable_safe(proxy_states, recoil_proxy_mt)
        gun.states = proxy_states

        local success, err = pcall_safe(self._original.recoil_function, gun, owner)

        gun.states = real_states

        if not success then
            warn("Recoil error:", err)
        end
    end)

    self._gunModule.send_shoot = newcclosure(function(gun)
        if not self._enabled then
            return self._original.send_shoot(gun)
        end
        if not gun or not gun.states then
            return self._original.send_shoot(gun)
        end

        local real_states = gun.states
        local real_accuracy = gun.accuracy

        local proxy_states = { __real_states = real_states }
        setmetatable_safe(proxy_states, spread_firerate_proxy_mt)

        gun.states = proxy_states
        gun.accuracy = perfect_accuracy

        local success, err = pcall_safe(self._original.send_shoot, gun)

        gun.states = real_states
        gun.accuracy = real_accuracy

        if not success then
            warn("Shoot error:", err)
        end
    end)

    self._gunModule.input_render = newcclosure(function(gun, ...)
        if not self._enabled then
            return self._original.input_render(gun, ...)
        end
        if not gun or not gun.states then
            return self._original.input_render(gun, ...)
        end

        local real_states = gun.states

        local proxy_states = { __real_states = real_states }
        setmetatable_safe(proxy_states, firerate_proxy_mt)

        gun.states = proxy_states

        local success, err = pcall_safe(self._original.input_render, gun, ...)

        gun.states = real_states

        if not success then
            warn("Render error:", err)
        end
    end)

    self._gunModule.reload_begin = newcclosure(function(gun, ...)
        if not self._enabled then
            return self._original.reload_begin(gun, ...)
        end
        if not gun or not gun.states then
            return self._original.reload_begin(gun, ...)
        end

        local real_states = gun.states

        local proxy_states = { __real_states = real_states }
        setmetatable_safe(proxy_states, reload_proxy_mt)

        gun.states = proxy_states

        local success, err = pcall_safe(self._original.reload_begin, gun, ...)

        gun.states = real_states

        if not success then
            warn("Reload error:", err)
        end
    end)

    self._gunModule.sights = newcclosure(function(gun, ...)
        if not self._enabled then
            return self._original.sights(gun, ...)
        end
        if not gun or not gun.states then
            return self._original.sights(gun, ...)
        end

        local real_states = gun.states

        local proxy_states = { __real_states = real_states }
        setmetatable_safe(proxy_states, sights_proxy_mt)

        gun.states = proxy_states

        local success, err = pcall_safe(self._original.sights, gun, ...)

        gun.states = real_states

        if not success then
            warn("Sights error:", err)
        end
    end)

    self._gunModule.update_sight_lens = newcclosure(function(gun, ...)
        if not self._enabled then
            return self._original.update_sight_lens(gun, ...)
        end
        if not gun or not gun.states then
            return self._original.update_sight_lens(gun, ...)
        end

        local real_states = gun.states

        local proxy_states = { __real_states = real_states }
        setmetatable_safe(proxy_states, sights_proxy_mt)

        gun.states = proxy_states

        local success, err = pcall_safe(self._original.update_sight_lens, gun, ...)

        gun.states = real_states

        if not success then
            warn("Update sight lens error:", err)
        end
    end)

    return true
end

function Module:init(force)
    if self._initialized and not force then
        return true
    end

    local okInstall, installErr = self:_installHooks()
    if not okInstall then
        return false, installErr
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

    if self._enabled and self.config.force_auto then
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
        if self.config[key] ~= nil then
            self.config[key] = value
        end
    end

    perfect_accuracy.Value = self.config.accuracy_multiplier

    if self._initialized and self._gunModule then
        if self._enabled and self.config.force_auto then
            self:_applyForceAuto(true)
        elseif self._originalAutomatic ~= nil then
            self:_applyForceAuto(self._originalAutomatic)
        end
    end

    return true
end

function Module:getConfig()
    return self.config
end

function Module:unload()
    if not self._initialized or not self._gunModule then
        return true
    end

    if self._original.recoil_function then self._gunModule.recoil_function = self._original.recoil_function end
    if self._original.send_shoot then self._gunModule.send_shoot = self._original.send_shoot end
    if self._original.input_render then self._gunModule.input_render = self._original.input_render end
    if self._original.reload_begin then self._gunModule.reload_begin = self._original.reload_begin end
    if self._original.sights then self._gunModule.sights = self._original.sights end
    if self._original.update_sight_lens then self._gunModule.update_sight_lens = self._original.update_sight_lens end
    if self._originalAutomatic ~= nil then self:_applyForceAuto(self._originalAutomatic) end

    self._initialized = false
    self._enabled = false
    return true
end

return Module

