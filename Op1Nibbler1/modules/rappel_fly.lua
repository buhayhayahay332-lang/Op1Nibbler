return function(ctx)
    local Runtime = ctx and ctx.Runtime or {}
    local cloneref = Runtime.cloneref or cloneref or function(obj)
        return obj
    end
    local clonefunc = Runtime.clonefunction or clonefunc or function(fn)
        return fn
    end
    local newcclosure = Runtime.newcclosure or newcclosure or function(fn)
        return fn
    end
    local hookfunction = Runtime.hookfunction or hookfunction or function(f, r)
        return f
    end
    local replaceclosure = Runtime.replaceclosure or replaceclosure or function(f, r)
        return f
    end
    local hookmetamethod = Runtime.hookmetamethod or hookmetamethod or function()
    end
    local getrawmetatable = Runtime.getrawmetatable or getrawmetatable or function()
        return {}
    end
    local setreadonly = Runtime.setreadonly or setreadonly or function()
    end
    local Instance_new = clonefunc(Instance.new)

    local Services = ctx and ctx.Services or {}
    local ReplicatedStorage = Services.ReplicatedStorage or cloneref(game:GetService("ReplicatedStorage"))
    local RunService = Services.RunService or cloneref(game:GetService("RunService"))
    local UserInputService = Services.UserInputService or cloneref(game:GetService("UserInputService"))
    local Players = Services.Players or cloneref(game:GetService("Players"))
    local Workspace = Services.Workspace or cloneref(game:GetService("Workspace"))
    local LocalPlayer = Players.LocalPlayer
    local GrappleModule = require(ReplicatedStorage.Modules.Items.Item.Utility.GrapplingHook)
    local camera = Workspace.CurrentCamera

    local CONFIG = {
        speed = 10,
        pull_speed = 0.5,
        fly_key = Enum.KeyCode.G
    }

    local M = {
        enabled = true,
        speed = CONFIG.speed,
        pullSpeed = CONFIG.pull_speed,
        flyKey = CONFIG.fly_key,
        _initialized = false
    }

    local flying = false
    local fly_connection
    local grapple_self_ref = nil
    local grapple_owner_ref = nil
    local old_walkspeed = nil
    local old_jumppower = nil
    local real_self_states = nil
    local real_owner_states = nil
    local tracked_humanoid = nil
    local dummy_event = Instance_new("BindableEvent")

    -- property spoofing
    local spoofed = {}

    local function spoof_property(instance, key, fake_value, real_value)
        if not spoofed[instance] then
            spoofed[instance] = {}
        end
        spoofed[instance][key] = fake_value
        instance[key] = real_value
    end

    local function clear_spoof(instance, key)
        if spoofed[instance] then
            spoofed[instance][key] = nil
            if next(spoofed[instance]) == nil then
                spoofed[instance] = nil
            end
        end
    end

    -- __index spoofing
    -- do NOT clonefunc mt.__index since its a C function not a Lua function
    -- wrap fallback in pcall so if it errors for any reason other modules dont break
    local mt = getrawmetatable(game)
    local old_index = mt.__index
    setreadonly(mt, false)
    mt.__index = newcclosure(function(self, key)
        if spoofed[self] and spoofed[self][key] ~= nil then
            return spoofed[self][key]
        end
        local ok, result = pcall(old_index, self, key)
        if ok then return result end
        return nil
    end)
    setreadonly(mt, true)

    -- __newindex spoofing
    local old_newindex = hookmetamethod(game, "__newindex", newcclosure(function(self, key, value)
        if flying and spoofed[self] and spoofed[self][key] ~= nil then
            return
        end
        return old_newindex(self, key, value)
    end))

    -- GetPropertyChangedSignal spoofing
    local old_gpcs = hookfunction(game.GetPropertyChangedSignal, newcclosure(function(self, property)
        if flying and spoofed[self] and spoofed[self][property] ~= nil then
            return dummy_event.Event
        end
        if flying and self == tracked_humanoid then
            if property == "WalkSpeed" or property == "JumpPower" then
                return dummy_event.Event
            end
        end
        return old_gpcs(self, property)
    end))

    local function get_wasd_direction()
        local direction = Vector3.new(0, 0, 0)
        local cam_cf = camera.CFrame

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            direction = direction + cam_cf.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            direction = direction - cam_cf.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            direction = direction - cam_cf.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            direction = direction + cam_cf.RightVector
        end

        if direction.Magnitude > 0 then
            direction = direction.Unit
        end

        return direction
    end

    local function make_state_proxy(real, set_intercept)
        return setmetatable({}, {
            __index = newcclosure(function(_, method)
                if method == "set" then
                    return function(_, value)
                        return set_intercept(real, value)
                    end
                end
                return real[method]
            end),
            __newindex = newcclosure(function(_, key, value)
                real[key] = value
            end),
            __metatable = "locked"
        })
    end

    local states_proxy_mt = {
        __index = newcclosure(function(t, key)
            local real = rawget(t, "__real_states")[key]
            if not real then return nil end

            if key == "rappeling" then
                return make_state_proxy(real, function(r, value)
                    if flying and value == false then return end
                    return r:set(value)
                end)
            end

            return real
        end),
        __newindex = newcclosure(function(t, key, value)
            rawget(t, "__real_states")[key] = value
        end),
        __metatable = "locked"
    }

    local owner_states_proxy_mt = {
        __index = newcclosure(function(t, key)
            local real = rawget(t, "__real_states")[key]
            if not real then return nil end

            if key == "climbing" then
                return make_state_proxy(real, function(r, value)
                    if flying and value == 0 then return end
                    return r:set(value)
                end)
            end

            if key == "vault" then
                return make_state_proxy(real, function(r, value)
                    if flying and value > 0 then return end
                    return r:set(value)
                end)
            end

            return real
        end),
        __newindex = newcclosure(function(t, key, value)
            rawget(t, "__real_states")[key] = value
        end),
        __metatable = "locked"
    }

    -- direct assignment for hook_inputs
    local old_hook_inputs = clonefunc(GrappleModule.hook_inputs)
    GrappleModule.hook_inputs = newcclosure(function(self, ...)
        grapple_self_ref = self
        grapple_owner_ref = self.owner
        return old_hook_inputs(self, ...)
    end)

    -- direct assignment for can_rappel
    local old_can_rappel = clonefunc(GrappleModule.can_rappel)
    GrappleModule.can_rappel = newcclosure(function(self, owner)
        if not flying then
            return old_can_rappel(self, owner)
        end

        local target = camera.CFrame.Position + camera.CFrame.LookVector * 100
        return CFrame.new(target), CFrame.new(target + Vector3.new(0, 2, 0))
    end)

    -- replaceclosure on start_rappel_mode
    local old_start_rappel = clonefunc(GrappleModule.start_rappel_mode)
    replaceclosure(GrappleModule.start_rappel_mode, newcclosure(function(self, owner, ...)
        return old_start_rappel(self, owner, ...)
    end))

    local function stop_flying()
        if not flying then return end
        flying = false

        if fly_connection then
            fly_connection:Disconnect()
            fly_connection = nil
        end

        local self = grapple_self_ref
        local owner = grapple_owner_ref

        if self then
            pcall(function()
                if real_self_states then
                    self.states = real_self_states
                    real_self_states = nil
                end
            end)

            pcall(function()
                if self.move_position then
                    clear_spoof(self.move_position, "MaxVelocity")
                    clear_spoof(self.move_position, "Responsiveness")
                    self.move_position.MaxVelocity = math.huge
                    self.move_position.Responsiveness = 200
                end
            end)

            pcall(function()
                if self.states then
                    self.states.rappeling:set(false)
                    self.states.hook:set(CFrame.new())
                end
            end)
        end

        if owner then
            pcall(function()
                if real_owner_states then
                    owner.states = real_owner_states
                    real_owner_states = nil
                end
            end)

            pcall(function()
                local humanoid = owner.instance:FindFirstChildOfClass("Humanoid")
                local root = owner.instance:FindFirstChild("HumanoidRootPart")
                if humanoid and root and root.Parent then
                    clear_spoof(humanoid, "WalkSpeed")
                    clear_spoof(humanoid, "JumpPower")
                    humanoid.WalkSpeed = old_walkspeed or 16
                    humanoid.JumpPower = old_jumppower or 50
                end
            end)
        end

        tracked_humanoid = nil
        old_walkspeed = nil
        old_jumppower = nil

        print("[Fly] Stopped")
    end

    local function start_flying()
        if not M.enabled then return end

        flying = true

        local self = grapple_self_ref
        local owner = grapple_owner_ref

        pcall(function()
            real_self_states = self.states
            self.states = setmetatable({ __real_states = real_self_states }, states_proxy_mt)
        end)

        pcall(function()
            real_owner_states = owner.states
            owner.states = setmetatable({ __real_states = real_owner_states }, owner_states_proxy_mt)
        end)

        pcall(function()
            local humanoid = owner.instance:FindFirstChildOfClass("Humanoid")
            if humanoid then
                tracked_humanoid = humanoid
                old_walkspeed = humanoid.WalkSpeed
                old_jumppower = humanoid.JumpPower
                spoof_property(humanoid, "WalkSpeed", old_walkspeed, 0)
                spoof_property(humanoid, "JumpPower", old_jumppower, 0)
            end
        end)

        pcall(function()
            if self.move_position then
                local fake_max = (spoofed[self.move_position] and spoofed[self.move_position].MaxVelocity)
                    or self.move_position.MaxVelocity
                local fake_resp = (spoofed[self.move_position] and spoofed[self.move_position].Responsiveness)
                    or self.move_position.Responsiveness
                spoof_property(self.move_position, "MaxVelocity", fake_max, CONFIG.pull_speed)
                spoof_property(self.move_position, "Responsiveness", fake_resp, 10)
            end
        end)

        local root = owner.instance:FindFirstChild("HumanoidRootPart")
        local current_target = root and root.Position or camera.CFrame.Position

        pcall(function()
            local stay_cf = CFrame.new(current_target)
            self:start_rappel_mode(owner, stay_cf, stay_cf)
        end)

        fly_connection = RunService.Heartbeat:Connect(newcclosure(function(dt)
            if not flying then
                fly_connection:Disconnect()
                return
            end

            local dir = get_wasd_direction()
            if dir.Magnitude > 0 then
                local rootPart = owner.instance:FindFirstChild("HumanoidRootPart")
                if rootPart then
                    local to_target = (current_target - rootPart.Position)
                    if to_target.Magnitude < 3 or dir.Magnitude > 0 then
                        current_target = current_target + dir * CONFIG.speed * dt
                    end
                end
            end

            pcall(function()
                if self.move_position then
                    self.move_position.Position = current_target
                end
            end)
        end))

        print("[Fly] Started")
    end

    -- auto stop on character removing
    LocalPlayer.CharacterRemoving:Connect(newcclosure(function(char)
        if not flying then return end
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        local root = char:FindFirstChild("HumanoidRootPart")
        if humanoid and root and root.Parent then
            clear_spoof(humanoid, "WalkSpeed")
            clear_spoof(humanoid, "JumpPower")
            humanoid.WalkSpeed = old_walkspeed or 16
            humanoid.JumpPower = old_jumppower or 50
        end
        stop_flying()
        print("[Fly] Auto-stopped on despawn")
    end))

    function M:Init()
        if self._initialized then return end

        UserInputService.InputBegan:Connect(newcclosure(function(input, processed)
            if processed or not M.enabled then return end

            if input.KeyCode == M.flyKey then
                if flying then
                    stop_flying()
                else
                    if grapple_self_ref and grapple_owner_ref then
                        start_flying()
                    else
                        print("[Fly] Equip grapple first")
                    end
                end
            end
        end))

        self._initialized = true
        print("[Fly] Loaded")
    end

    function M:SetEnabled(state)
        state = state and true or false
        M.enabled = state
        if not state and flying then
            stop_flying()
        end
    end

    function M:SetSpeed(value)
        CONFIG.speed = value
        self.speed = value
    end

    function M:SetPullSpeed(value)
        CONFIG.pull_speed = value
        self.pullSpeed = value
        if flying and grapple_self_ref and grapple_self_ref.move_position then
            local move_pos = grapple_self_ref.move_position
            local fake = (spoofed[move_pos] and spoofed[move_pos].MaxVelocity) or move_pos.MaxVelocity
            spoof_property(move_pos, "MaxVelocity", fake, CONFIG.pull_speed)
        end
    end

    return M
end