return function(ctx)
    local GunModule = ctx.GunModule

    local M = {
        enabled = false,
        hooked = false,
        recoilReduction = 0,
        horizontalRecoil = 0,
        noSpread = true,
        accuracyMultiplier = 1,
        customFirerate = 1200,
        reloadSpeed = 0.1,
        forceAuto = true,
        instantADS = true,
        customZoom = 1.5,
        original = {}
    }

    local function proxyStates(states, map)
        return setmetatable({ __states = states }, {
            __index = function(t, key)
                local state = rawget(t, "__states")[key]
                if type(state) == "table" and state.get and map[key] then
                    return {
                        get = function()
                            return map[key](state.get)
                        end
                    }
                end
                return state
            end,
            __metatable = "locked"
        })
    end

    function M:Init()
        if self.hooked or not GunModule then
            return
        end

        self.original.recoil_function = GunModule.recoil_function
        self.original.send_shoot = GunModule.send_shoot
        self.original.input_render = GunModule.input_render
        self.original.reload_begin = GunModule.reload_begin
        self.original.sights = GunModule.sights
        self.original.update_sight_lens = GunModule.update_sight_lens

        GunModule.recoil_function = newcclosure(function(gunSelf, owner)
            if not gunSelf or not gunSelf.states then
                return M.original.recoil_function(gunSelf, owner)
            end

            local realStates = gunSelf.states
            gunSelf.states = proxyStates(realStates, {
                recoil_up = function(defaultGet)
                    local val = defaultGet()
                    if not M.enabled then
                        return val
                    end
                    return (type(val) == "number" and val * M.recoilReduction) or 0
                end,
                recoil_side = function(defaultGet)
                    return M.enabled and M.horizontalRecoil or defaultGet()
                end
            })

            local ok, err = pcall(M.original.recoil_function, gunSelf, owner)
            gunSelf.states = realStates
            if not ok then
                warn("[Op1Nibbler] recoil_function error:", err)
            end
        end)

        GunModule.send_shoot = newcclosure(function(gunSelf)
            if not gunSelf or not gunSelf.states then
                return M.original.send_shoot(gunSelf)
            end

            local realStates = gunSelf.states
            local realAccuracy = gunSelf.accuracy

            gunSelf.states = proxyStates(realStates, {
                spread = function(defaultGet)
                    if M.enabled and M.noSpread then
                        return 0
                    end
                    return defaultGet()
                end,
                firerate = function(defaultGet)
                    return M.enabled and M.customFirerate or defaultGet()
                end
            })

            if M.enabled then
                gunSelf.accuracy = { Value = M.accuracyMultiplier }
            end

            local ok, err = pcall(M.original.send_shoot, gunSelf)
            gunSelf.states, gunSelf.accuracy = realStates, realAccuracy
            if not ok then
                warn("[Op1Nibbler] send_shoot error:", err)
            end
        end)

        GunModule.input_render = newcclosure(function(gunSelf, ...)
            if not gunSelf or not gunSelf.states then
                return M.original.input_render(gunSelf, ...)
            end

            local realStates = gunSelf.states
            gunSelf.states = proxyStates(realStates, {
                firerate = function(defaultGet)
                    return M.enabled and M.customFirerate or defaultGet()
                end
            })

            if M.enabled and M.forceAuto then
                gunSelf.automatic = true
            end

            local ok, err = pcall(M.original.input_render, gunSelf, ...)
            gunSelf.states = realStates
            if not ok then
                warn("[Op1Nibbler] input_render error:", err)
            end
        end)

        GunModule.reload_begin = newcclosure(function(gunSelf, ...)
            if not gunSelf or not gunSelf.states then
                return M.original.reload_begin(gunSelf, ...)
            end

            local realStates = gunSelf.states
            gunSelf.states = proxyStates(realStates, {
                reload_speed = function(defaultGet)
                    return M.enabled and M.reloadSpeed or defaultGet()
                end
            })

            local ok, err = pcall(M.original.reload_begin, gunSelf, ...)
            gunSelf.states = realStates
            if not ok then
                warn("[Op1Nibbler] reload_begin error:", err)
            end
        end)

        local function sightWrapper(originalFn)
            return newcclosure(function(gunSelf, ...)
                if not gunSelf or not gunSelf.states then
                    return originalFn(gunSelf, ...)
                end

                local realStates = gunSelf.states
                gunSelf.states = proxyStates(realStates, {
                    ads = function(defaultGet)
                        if M.enabled and M.instantADS then
                            return 0.01
                        end
                        return defaultGet()
                    end,
                    zoom = function(defaultGet)
                        return M.enabled and M.customZoom or defaultGet()
                    end
                })

                local ok, err = pcall(originalFn, gunSelf, ...)
                gunSelf.states = realStates
                if not ok then
                    warn("[Op1Nibbler] sight function error:", err)
                end
            end)
        end

        GunModule.sights = sightWrapper(M.original.sights)
        GunModule.update_sight_lens = sightWrapper(M.original.update_sight_lens)

        self.hooked = true
    end

    return M
end
