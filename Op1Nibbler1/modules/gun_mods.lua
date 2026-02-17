return function(ctx)
    local CONFIG = {
        recoil_reduction = 0,
        horizontal_recoil = 0,
        no_spread = true,
        accuracy_multiplier = 1,
        custom_firerate = 1200,
        reload_speed = 0.1,
        force_auto = true,
        instant_ads = true,
        custom_zoom = 1.5
    }

    local cloneref = cloneref
    local clonefunction = clonefunction
    local newcclosure = newcclosure
    local pcall = clonefunction(pcall)
    local setmetatable = clonefunction(setmetatable)
    local typeof = clonefunction(typeof)
    local rawget = clonefunction(rawget)

    local ReplicatedStorage = cloneref(game:GetService("ReplicatedStorage"))
    local UserInputService = cloneref(game:GetService("UserInputService"))
    local Workspace = cloneref(game:GetService("Workspace"))

    local GunModule = ctx.GunModule or require(ReplicatedStorage.Modules.Items.Item.Gun)

    local original_recoil_function = clonefunction(GunModule.recoil_function)
    local original_send_shoot = clonefunction(GunModule.send_shoot)
    local original_input_render = clonefunction(GunModule.input_render)
    local original_reload_begin = clonefunction(GunModule.reload_begin)
    local original_sights = clonefunction(GunModule.sights)
    local original_update_sight_lens = clonefunction(GunModule.update_sight_lens)

    local M

    local recoil_up_get = newcclosure(function(original_state)
        local val = original_state:get()
        if M and not M.enabled then
            return val
        end
        return (typeof(val) == "number" and val * CONFIG.recoil_reduction) or 0
    end)

    local recoil_side_get = newcclosure(function(original_state)
        if M and not M.enabled then
            return original_state:get()
        end
        return CONFIG.horizontal_recoil
    end)

    local spread_get = newcclosure(function(original_state)
        if M and not M.enabled then
            return original_state:get()
        end
        return CONFIG.no_spread and 0 or original_state:get()
    end)

    local firerate_get = newcclosure(function(original_state)
        if M and not M.enabled then
            return original_state:get()
        end
        return CONFIG.custom_firerate
    end)

    local reload_speed_get = newcclosure(function(original_state)
        if M and not M.enabled then
            return original_state:get()
        end
        return CONFIG.reload_speed
    end)

    local ads_get = newcclosure(function(original_state)
        if M and not M.enabled then
            return original_state:get()
        end
        return CONFIG.instant_ads and 0.01 or original_state:get()
    end)

    local zoom_get = newcclosure(function(original_state)
        if M and not M.enabled then
            return original_state:get()
        end
        return CONFIG.custom_zoom
    end)

    local perfect_accuracy = { Value = CONFIG.accuracy_multiplier }

    local recoil_proxy_mt = {
        __index = newcclosure(function(t, key)
            local real_states = rawget(t, "__real_states")
            if not real_states then return nil end

            local state = real_states[key]
            if typeof(state) == "table" and state.get then
                if key == "recoil_up" then
                    return { get = function() return recoil_up_get(state) end }
                elseif key == "recoil_side" then
                    return { get = function() return recoil_side_get(state) end }
                end
            end
            return state
        end),
        __metatable = "locked"
    }

    local spread_firerate_proxy_mt = {
        __index = newcclosure(function(t, key)
            local real_states = rawget(t, "__real_states")
            if not real_states then return nil end

            local state = real_states[key]
            if typeof(state) == "table" and state.get then
                if key == "spread" then
                    return { get = function() return spread_get(state) end }
                elseif key == "firerate" then
                    return { get = function() return firerate_get(state) end }
                end
            end
            return state
        end),
        __metatable = "locked"
    }

    local firerate_proxy_mt = {
        __index = newcclosure(function(t, key)
            local real_states = rawget(t, "__real_states")
            if not real_states then return nil end

            local state = real_states[key]
            if typeof(state) == "table" and state.get and key == "firerate" then
                return { get = function() return firerate_get(state) end }
            end
            return state
        end),
        __metatable = "locked"
    }

    local reload_proxy_mt = {
        __index = newcclosure(function(t, key)
            local real_states = rawget(t, "__real_states")
            if not real_states then return nil end

            local state = real_states[key]
            if typeof(state) == "table" and state.get and key == "reload_speed" then
                return { get = function() return reload_speed_get(state) end }
            end
            return state
        end),
        __metatable = "locked"
    }

    local sights_proxy_mt = {
        __index = newcclosure(function(t, key)
            local real_states = rawget(t, "__real_states")
            if not real_states then return nil end

            local state = real_states[key]
            if typeof(state) == "table" and state.get then
                if key == "ads" then
                    return { get = function() return ads_get(state) end }
                elseif key == "zoom" then
                    return { get = function() return zoom_get(state) end }
                end
            end
            return state
        end),
        __metatable = "locked"
    }

    M = {
        enabled = true,
        recoilReduction = CONFIG.recoil_reduction,
        horizontalRecoil = CONFIG.horizontal_recoil,
        noSpread = CONFIG.no_spread,
        accuracyMultiplier = CONFIG.accuracy_multiplier,
        customFirerate = CONFIG.custom_firerate,
        reloadSpeed = CONFIG.reload_speed,
        forceAuto = CONFIG.force_auto,
        instantADS = CONFIG.instant_ads,
        customZoom = CONFIG.custom_zoom,
        _initialized = false
    }

    local function hookFunctions()
        GunModule.recoil_function = newcclosure(function(self, owner)
            if not self or not self.states then
                return original_recoil_function(self, owner)
            end

            local real_states = self.states
            local proxy_states = { __real_states = real_states }
            setmetatable(proxy_states, recoil_proxy_mt)
            self.states = proxy_states

            local success, err = pcall(original_recoil_function, self, owner)
            self.states = real_states

            if not success then
                warn("Recoil error:", err)
            end
        end)

        GunModule.send_shoot = newcclosure(function(self)
            if not self or not self.states then
                return original_send_shoot(self)
            end

            local real_states = self.states
            local real_accuracy = self.accuracy

            local proxy_states = { __real_states = real_states }
            setmetatable(proxy_states, spread_firerate_proxy_mt)

            self.states = proxy_states
            if M.enabled then
                self.accuracy = perfect_accuracy
            end

            local success, err = pcall(original_send_shoot, self)

            self.states = real_states
            self.accuracy = real_accuracy

            if not success then
                warn("Shoot error:", err)
            end
        end)

        GunModule.input_render = newcclosure(function(self, ...)
            if not self or not self.states then
                return original_input_render(self, ...)
            end

            local real_states = self.states
            local proxy_states = { __real_states = real_states }
            setmetatable(proxy_states, firerate_proxy_mt)
            self.states = proxy_states

            local success, err = pcall(original_input_render, self, ...)
            self.states = real_states

            if not success then
                warn("Render error:", err)
            end
        end)

        GunModule.reload_begin = newcclosure(function(self, ...)
            if not self or not self.states then
                return original_reload_begin(self, ...)
            end

            local real_states = self.states
            local proxy_states = { __real_states = real_states }
            setmetatable(proxy_states, reload_proxy_mt)
            self.states = proxy_states

            local success, err = pcall(original_reload_begin, self, ...)
            self.states = real_states

            if not success then
                warn("Reload error:", err)
            end
        end)

        GunModule.sights = newcclosure(function(self, ...)
            if not self or not self.states then
                return original_sights(self, ...)
            end

            local real_states = self.states
            local proxy_states = { __real_states = real_states }
            setmetatable(proxy_states, sights_proxy_mt)
            self.states = proxy_states

            local success, err = pcall(original_sights, self, ...)
            self.states = real_states

            if not success then
                warn("Sights error:", err)
            end
        end)

        GunModule.update_sight_lens = newcclosure(function(self, ...)
            if not self or not self.states then
                return original_update_sight_lens(self, ...)
            end

            local real_states = self.states
            local proxy_states = { __real_states = real_states }
            setmetatable(proxy_states, sights_proxy_mt)
            self.states = proxy_states

            local success, err = pcall(original_update_sight_lens, self, ...)
            self.states = real_states

            if not success then
                warn("Update sight lens error:", err)
            end
        end)
    end

    function M:Init()
        if self._initialized then
            return
        end

        hookFunctions()
        if CONFIG.force_auto then
            GunModule.automatic = true
        end
        self._initialized = true
    end

    function M:SetEnabled(value)
        self.enabled = value and true or false
    end

    function M:SetRecoilReduction(value)
        CONFIG.recoil_reduction = value
        self.recoilReduction = value
    end

    function M:SetHorizontalRecoil(value)
        CONFIG.horizontal_recoil = value
        self.horizontalRecoil = value
    end

    function M:SetNoSpread(value)
        CONFIG.no_spread = value and true or false
        self.noSpread = CONFIG.no_spread
    end

    function M:SetAccuracyMultiplier(value)
        CONFIG.accuracy_multiplier = value
        perfect_accuracy.Value = value
        self.accuracyMultiplier = value
    end

    function M:SetCustomFirerate(value)
        CONFIG.custom_firerate = value
        self.customFirerate = value
    end

    function M:SetReloadSpeed(value)
        CONFIG.reload_speed = value
        self.reloadSpeed = value
    end

    function M:SetForceAuto(value)
        CONFIG.force_auto = value and true or false
        self.forceAuto = CONFIG.force_auto
        if CONFIG.force_auto then
            GunModule.automatic = true
        end
    end

    function M:SetInstantADS(value)
        CONFIG.instant_ads = value and true or false
        self.instantADS = CONFIG.instant_ads
    end

    function M:SetCustomZoom(value)
        CONFIG.custom_zoom = value
        self.customZoom = value
    end

    return M
end
