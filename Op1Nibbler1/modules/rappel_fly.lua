return function(ctx)
local Runtime = ctx and ctx.Runtime or {}
local cloneref = Runtime.cloneref or cloneref or function(obj) return obj end
local clonefunc = Runtime.clonefunction or clonefunc or function(fn) return fn end
local newcclosure = Runtime.newcclosure or newcclosure or function(fn) return fn end
local hookfunction = Runtime.hookfunction or hookfunction or function(f, r) return f end
local replaceclosure = Runtime.replaceclosure or replaceclosure or function(f, r) return f end

local Services = ctx and ctx.Services or {}
local ReplicatedStorage = Services.ReplicatedStorage or cloneref(game:GetService("ReplicatedStorage"))
local RunService = Services.RunService or cloneref(game:GetService("RunService"))
local UserInputService = Services.UserInputService or cloneref(game:GetService("UserInputService"))
local Players = Services.Players or cloneref(game:GetService("Players"))
local LocalPlayer = Players.LocalPlayer
local GrappleModule = require(ReplicatedStorage.Modules.Items.Item.Utility.GrapplingHook)
local camera = (Services.Workspace or cloneref(workspace)).CurrentCamera

-- locate the grapple start function (game updates renamed this a few times)
local start_rappel_method = nil
for _, name in ipairs({ "start_rappel_mode", "start_rappel", "StartRappelMode", "StartRappel" }) do
    if typeof(GrappleModule[name]) == "function" then
        start_rappel_method = name
        break
    end
end

local config = {
    speed = 10,
    pull_speed = 0.5,
    fly_key = Enum.KeyCode.G
}

local M = {
    enabled = false,
    speed = config.speed,
    pullSpeed = config.pull_speed
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
local dummy_event = Instance.new("BindableEvent")
-- weak-key table so destroyed humanoids don't leak
local spoofed_humanoid_props = setmetatable({}, { __mode = "k" })

-- optional property spoofing (mirror hitbox style) so WalkSpeed/JumpPower reads stay original while flying
do
    -- install once globally; avoid stacking hooks across reloads
    local hookmetamethod = Runtime.hookmetamethod or hookmetamethod
    local getrawmetatable = Runtime.getrawmetatable or getrawmetatable
    local setreadonly = Runtime.setreadonly or setreadonly
    if hookmetamethod and getrawmetatable and setreadonly and not _G.RF_SPOOF_INSTALLED then
        local mt = getrawmetatable(game)
        if mt and mt.__index then
            local old_index = mt.__index
            _G.RF_OLD_INDEX = _G.RF_OLD_INDEX or old_index
            setreadonly(mt, false)
            mt.__index = newcclosure(function(self, key)
                local data = spoofed_humanoid_props[self]
                if data then
                    if key == "WalkSpeed" then
                        return data.WalkSpeed
                    elseif key == "JumpPower" then
                        return data.JumpPower
                    end
                end
                return _G.RF_OLD_INDEX(self, key)
            end)
            setreadonly(mt, true)
            _G.RF_SPOOF_INSTALLED = true
        end
    end
end

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
                return function(s, value)
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

-- bindable event blocks listeners from being notified when WalkSpeed or JumpPower changes
local old_gpcs = hookfunction(game.GetPropertyChangedSignal, newcclosure(function(self, property)
    if flying and self == tracked_humanoid then
        if property == "WalkSpeed" or property == "JumpPower" then
            return dummy_event.Event
        end
    end
    return old_gpcs(self, property)
end))

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
    if not M.enabled or not flying then
        return old_can_rappel(self, owner)
    end

    local target = camera.CFrame.Position + camera.CFrame.LookVector * 100
    return CFrame.new(target), CFrame.new(target + Vector3.new(0, 2, 0))
end)

-- replaceclosure on start_rappel_mode (when present)
local old_start_rappel = nil
if start_rappel_method then
    old_start_rappel = clonefunc(GrappleModule[start_rappel_method])
    replaceclosure(GrappleModule[start_rappel_method], newcclosure(function(self, owner, ...)
        if old_start_rappel then
            return old_start_rappel(self, owner, ...)
        end
    end))
else
    print("[Fly] Warning: Grapple module missing start_rappel function")
end

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
                self.move_position.MaxVelocity = math.huge
                self.move_position.Responsiveness = 0
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

        -- check character is still intact before restoring humanoid
        -- game's Character module errors if HumanoidRootPart is gone
        pcall(function()
            local humanoid = owner.instance:FindFirstChildOfClass("Humanoid")
            local root = owner.instance:FindFirstChild("HumanoidRootPart")
            if humanoid and root and root.Parent then
                humanoid.WalkSpeed = old_walkspeed or 16
                humanoid.JumpPower = old_jumppower or 50
            end
            spoofed_humanoid_props[humanoid] = nil
        end)
    end

    tracked_humanoid = nil
    old_walkspeed = nil
    old_jumppower = nil

    print("[Fly] Stopped")
end

local function start_flying()
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
            humanoid.WalkSpeed = 0
            humanoid.JumpPower = 0
            spoofed_humanoid_props[humanoid] = {
                WalkSpeed = old_walkspeed,
                JumpPower = old_jumppower
            }
        end
    end)

    pcall(function()
        if self.move_position then
            self.move_position.MaxVelocity = config.pull_speed
            self.move_position.Responsiveness = 10
        end
    end)

    local root = owner.instance:FindFirstChild("HumanoidRootPart")
    local current_target = root and root.Position or camera.CFrame.Position

    if start_rappel_method then
        pcall(function()
            local stay_cf = CFrame.new(current_target)
            local fn = self[start_rappel_method]
            if typeof(fn) == "function" then
                fn(self, owner, stay_cf, stay_cf)
            end
        end)
    end

    local accum = 0
    fly_connection = RunService.Heartbeat:Connect(newcclosure(function(dt)
        if not flying then
            fly_connection:Disconnect()
            return
        end

        -- fail-safe: auto-stop if humanoid is dead
        if tracked_humanoid and tracked_humanoid.Health <= 0 then
            stop_flying()
            print("stopped flying humanoid died")
            return
        end

        -- throttle updates to ~30 Hz to reduce per-frame cost
        accum = accum + dt
        if accum < (1/30) then
            return
        end
        accum = 0

        local dir = get_wasd_direction()
        if dir.Magnitude > 0 then
            local root = owner.instance:FindFirstChild("HumanoidRootPart")
            if root then
                local to_target = (current_target - root.Position)
                if to_target.Magnitude < 3 or dir.Magnitude > 0 then
                    current_target = current_target + dir * config.speed * dt
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

-- auto-stop on death only using humanoid.Died
-- fires while character is still intact unlike CharacterRemoving
LocalPlayer.CharacterRemoving:Connect(newcclosure(function(char)
    if flying then
        -- char is the OLD character, still intact at this point
        local humanoid = char:FindFirstChildOfClass("Humanoid")
        local root = char:FindFirstChild("HumanoidRootPart")
        if humanoid and root and root.Parent then
            humanoid.WalkSpeed = old_walkspeed 
            humanoid.JumpPower = old_jumppower 
        end
        stop_flying()
        print("[Fly] Auto-stopped on character removing")
    end
end))
-- also handle existing character on script load
if LocalPlayer.Character then
    local humanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        humanoid.Died:Connect(newcclosure(function()
            if flying then
                stop_flying()
                print("[Fly] Auto-stopped on death")
            end
        end))
    end
end

UserInputService.InputBegan:Connect(newcclosure(function(input, processed)
    if processed or not M.enabled then return end

    if input.KeyCode == config.fly_key then
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

function M:SetEnabled(state)
    self.enabled = state and true or false
    if not self.enabled and flying then
        stop_flying()
    end
end

function M:SetSpeed(value)
    self.speed = tonumber(value) or self.speed
    config.speed = self.speed
end

function M:SetPullSpeed(value)
    self.pullSpeed = tonumber(value) or self.pullSpeed
    config.pull_speed = self.pullSpeed
    if flying and grapple_self_ref and grapple_self_ref.move_position then
        pcall(function()
            grapple_self_ref.move_position.MaxVelocity = config.pull_speed
        end)
    end
end

function M:Init()
    -- hooks are installed on require; nothing else needed here
end

print("[Fly] Loaded")

return M
end
