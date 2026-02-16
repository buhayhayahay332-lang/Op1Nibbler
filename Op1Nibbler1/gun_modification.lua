local cloneref = cloneref or function(obj) return obj end
local clonefunction = clonefunction or function(fn) return fn end
local newcclosure = newcclosure or function(fn) return fn end

local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))

local Module = {
    _initialized = false,
    _enabled = true,
    _gunModule = nil,
    _original = {},
    _originalAutomatic = nil,
    config = {
        recoil_reduction = 0,
        horizontal_recoil = 0,
        no_spread = true,
        accuracy_multiplier = 1,
        custom_firerate = 1200,
        reload_speed = 0.1,
        force_auto = true,
        instant_ads = true,
        custom_zoom = 1.5,
    },
}

local recoil_proxy_mt, spread_firerate_proxy_mt, firerate_proxy_mt, reload_proxy_mt, sights_proxy_mt

function Module:_cloneCallable(ref)
    if type(ref) ~= "function" then
        return ref
    end

    local ok, cloned = pcall(clonefunction, ref)
    if ok and cloned then
        return cloned
    end
    return ref
end

function Module:_setAutomaticValue(target, value)
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

function Module:_applyForceAutoToGun(gun, value)
    if not gun then
        return
    end

    if gun.automatic ~= nil then
        local replacement = self:_setAutomaticValue(gun.automatic, value)
        if replacement ~= nil then
            gun.automatic = replacement
        end
    end

    if gun.states and gun.states.automatic ~= nil then
        local replacement = self:_setAutomaticValue(gun.states.automatic, value)
        if replacement ~= nil then
            gun.states.automatic = replacement
        end
    end
end

function Module:_applyForceAutoToModule(value)
    if not self._gunModule then
        return
    end

    if self._gunModule.automatic ~= nil then
        local replacement = self:_setAutomaticValue(self._gunModule.automatic, value)
        if replacement ~= nil then
            self._gunModule.automatic = replacement
        else
            pcall(function()
                self._gunModule.automatic = value
            end)
        end
    end
end

function Module:_buildMetatables()
    local function recoil_up_get(original_state)
        local val = original_state:get()
        return (typeof(val) == "number" and val * self.config.recoil_reduction) or 0
    end

    local function recoil_side_get()
        return self.config.horizontal_recoil
    end

    local function spread_get()
        return self.config.no_spread and 0 or 1
    end

    local function firerate_get()
        return self.config.custom_firerate
    end

    local function reload_speed_get()
        return self.config.reload_speed
    end

    local function ads_get()
        return self.config.instant_ads and 0.01 or 0.3
    end

    local function zoom_get()
        return self.config.custom_zoom
    end

    recoil_proxy_mt = {
        __index = newcclosure(function(t, key)
            local real_states = rawget(t, "__real_states")
            if not real_states then return nil end

            local state = real_states[key]
            if self._enabled and typeof(state) == "table" and state.get then
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
            if self._enabled and typeof(state) == "table" and state.get then
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
            if self._enabled and typeof(state) == "table" and state.get and key == "firerate" then
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
            if self._enabled and typeof(state) == "table" and state.get and key == "reload_speed" then
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
            if self._enabled and typeof(state) == "table" and state.get then
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

local function callOriginal(ref, ...)
    local result = table.pack(pcall(ref, ...))
    if not result[1] then
        warn("GunMod hook error:", result[2])
        return nil
    end
    return table.unpack(result, 2, result.n)
end

function Module:_installHooks()
    local okRequire, gunModuleOrErr = pcall(function()
        return require(ReplicatedStorage.Modules.Items.Item.Gun)
    end)
    if not okRequire or type(gunModuleOrErr) ~= "table" then
        return false, "gun module require failed: " .. tostring(gunModuleOrErr)
    end

    self._gunModule = gunModuleOrErr
    self._original.recoil_function = self:_cloneCallable(self._gunModule.recoil_function)
    self._original.send_shoot = self:_cloneCallable(self._gunModule.send_shoot)
    self._original.input_render = self:_cloneCallable(self._gunModule.input_render)
    self._original.reload_begin = self:_cloneCallable(self._gunModule.reload_begin)
    self._original.sights = self:_cloneCallable(self._gunModule.sights)
    self._original.update_sight_lens = self:_cloneCallable(self._gunModule.update_sight_lens)
    self._originalAutomatic = self._gunModule.automatic

    self:_buildMetatables()

    self._gunModule.recoil_function = newcclosure(function(gun, owner)
        if not gun or not gun.states then
            return callOriginal(self._original.recoil_function, gun, owner)
        end

        if self.config.force_auto then
            self:_applyForceAutoToGun(gun, true)
        end

        local real_states = gun.states
        local proxy_states = { __real_states = real_states }
        setmetatable(proxy_states, recoil_proxy_mt)
        gun.states = proxy_states
        local out = callOriginal(self._original.recoil_function, gun, owner)
        gun.states = real_states
        return out
    end)

    self._gunModule.send_shoot = newcclosure(function(gun)
        if not gun or not gun.states then
            return callOriginal(self._original.send_shoot, gun)
        end

        if self.config.force_auto then
            self:_applyForceAutoToGun(gun, true)
        end

        local real_states = gun.states
        local real_accuracy = gun.accuracy
        local proxy_states = { __real_states = real_states }
        setmetatable(proxy_states, spread_firerate_proxy_mt)
        gun.states = proxy_states
        gun.accuracy = { Value = self.config.accuracy_multiplier }
        local out = callOriginal(self._original.send_shoot, gun)
        gun.states = real_states
        gun.accuracy = real_accuracy
        return out
    end)

    self._gunModule.input_render = newcclosure(function(gun, ...)
        if not gun or not gun.states then
            return callOriginal(self._original.input_render, gun, ...)
        end

        if self.config.force_auto then
            self:_applyForceAutoToGun(gun, true)
        end

        local real_states = gun.states
        local proxy_states = { __real_states = real_states }
        setmetatable(proxy_states, firerate_proxy_mt)
        gun.states = proxy_states
        local out = callOriginal(self._original.input_render, gun, ...)
        gun.states = real_states
        return out
    end)

    self._gunModule.reload_begin = newcclosure(function(gun, ...)
        if not gun or not gun.states then
            return callOriginal(self._original.reload_begin, gun, ...)
        end

        if self.config.force_auto then
            self:_applyForceAutoToGun(gun, true)
        end

        local real_states = gun.states
        local proxy_states = { __real_states = real_states }
        setmetatable(proxy_states, reload_proxy_mt)
        gun.states = proxy_states
        local out = callOriginal(self._original.reload_begin, gun, ...)
        gun.states = real_states
        return out
    end)

    self._gunModule.sights = newcclosure(function(gun, ...)
        if not gun or not gun.states then
            return callOriginal(self._original.sights, gun, ...)
        end

        if self.config.force_auto then
            self:_applyForceAutoToGun(gun, true)
        end

        local real_states = gun.states
        local proxy_states = { __real_states = real_states }
        setmetatable(proxy_states, sights_proxy_mt)
        gun.states = proxy_states
        local out = callOriginal(self._original.sights, gun, ...)
        gun.states = real_states
        return out
    end)

    self._gunModule.update_sight_lens = newcclosure(function(gun, ...)
        if not gun or not gun.states then
            return callOriginal(self._original.update_sight_lens, gun, ...)
        end

        if self.config.force_auto then
            self:_applyForceAutoToGun(gun, true)
        end

        local real_states = gun.states
        local proxy_states = { __real_states = real_states }
        setmetatable(proxy_states, sights_proxy_mt)
        gun.states = proxy_states
        local out = callOriginal(self._original.update_sight_lens, gun, ...)
        gun.states = real_states
        return out
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
    if self.config.force_auto then
        self:_applyForceAutoToModule(true)
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
    if self._enabled and self.config.force_auto then
        self:_applyForceAutoToModule(true)
    elseif not self._enabled and self._originalAutomatic ~= nil then
        self:_applyForceAutoToModule(self._originalAutomatic)
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

    if self._initialized and self._gunModule then
        if self.config.force_auto and self._enabled then
            self:_applyForceAutoToModule(true)
        elseif self._originalAutomatic ~= nil and (not self._enabled or not self.config.force_auto) then
            self:_applyForceAutoToModule(self._originalAutomatic)
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
    if self._originalAutomatic ~= nil then self:_applyForceAutoToModule(self._originalAutomatic) end

    self._initialized = false
    self._enabled = false
    return true
end

return Module
