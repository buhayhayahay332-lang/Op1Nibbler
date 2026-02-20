return function(ctx)
    local cloneref = cloneref or function(obj)
        return obj
    end
    local clonefunc = clonefunc or clonefunction or function(fn)
        return fn
    end
    local newcclosure = newcclosure or function(fn)
        return fn
    end
    local replaceclosure = replaceclosure or function()
    end

    local ReplicatedStorage = (ctx and ctx.Services and ctx.Services.ReplicatedStorage) or cloneref(game:GetService("ReplicatedStorage"))
    local RunService = (ctx and ctx.Services and ctx.Services.RunService) or cloneref(game:GetService("RunService"))
    local UserInputService = (ctx and ctx.Services and ctx.Services.UserInputService) or cloneref(game:GetService("UserInputService"))
    local Players = cloneref(game:GetService("Players"))
    local LocalPlayer = Players.LocalPlayer
    local camera = cloneref(workspace).CurrentCamera

    local M = {
        enabled = false,
        speed = 10,
        pullSpeed = 0.5,
        flyKey = Enum.KeyCode.G
    }

    local GrappleModule
    local initialized = false
    local hooksReady = false
    local flying = false
    local flyConnection
    local inputConnection

    local grappleSelfRef = nil
    local grappleOwnerRef = nil
    local oldWalkspeed = nil
    local oldJumppower = nil
    local realSelfStates = nil
    local realOwnerStates = nil
    local trackedHumanoid = nil
    local dummyEvent = Instance.new("BindableEvent")

    local function getWasdDirection()
        local direction = Vector3.new(0, 0, 0)
        local camCf = camera.CFrame

        if UserInputService:IsKeyDown(Enum.KeyCode.W) then
            direction = direction + camCf.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then
            direction = direction - camCf.LookVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then
            direction = direction - camCf.RightVector
        end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then
            direction = direction + camCf.RightVector
        end

        if direction.Magnitude > 0 then
            direction = direction.Unit
        end

        return direction
    end

    local function makeStateProxy(real, setIntercept)
        return setmetatable({}, {
            __index = newcclosure(function(_, method)
                if method == "set" then
                    return function(_, value)
                        return setIntercept(real, value)
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

    local statesProxyMt = {
        __index = newcclosure(function(t, key)
            local real = rawget(t, "__real_states")[key]
            if not real then
                return nil
            end

            if key == "rappeling" then
                return makeStateProxy(real, function(r, value)
                    if flying and value == false then
                        return
                    end
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

    local ownerStatesProxyMt = {
        __index = newcclosure(function(t, key)
            local real = rawget(t, "__real_states")[key]
            if not real then
                return nil
            end

            if key == "climbing" then
                return makeStateProxy(real, function(r, value)
                    if flying and value == 0 then
                        return
                    end
                    return r:set(value)
                end)
            end

            if key == "vault" then
                return makeStateProxy(real, function(r, value)
                    if flying and value > 0 then
                        return
                    end
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

    local function stopFlying()
        if not flying then
            return
        end
        flying = false

        if flyConnection then
            flyConnection:Disconnect()
            flyConnection = nil
        end

        local selfRef = grappleSelfRef
        local owner = grappleOwnerRef

        if selfRef then
            pcall(function()
                if realSelfStates then
                    selfRef.states = realSelfStates
                    realSelfStates = nil
                end
            end)

            pcall(function()
                if selfRef.move_position then
                    selfRef.move_position.MaxVelocity = math.huge
                    selfRef.move_position.Responsiveness = 0
                end
            end)

            pcall(function()
                if selfRef.states then
                    selfRef.states.rappeling:set(false)
                    selfRef.states.hook:set(CFrame.new())
                end
            end)
        end

        if owner then
            pcall(function()
                if realOwnerStates then
                    owner.states = realOwnerStates
                    realOwnerStates = nil
                end
            end)

            pcall(function()
                local humanoid = owner.instance:FindFirstChildOfClass("Humanoid")
                local root = owner.instance:FindFirstChild("HumanoidRootPart")
                if humanoid and root and root.Parent then
                    humanoid.WalkSpeed = oldWalkspeed or 16
                    humanoid.JumpPower = oldJumppower or 50
                end
            end)
        end

        trackedHumanoid = nil
        oldWalkspeed = nil
        oldJumppower = nil
    end

    local function startFlying()
        if flying then
            return
        end

        local selfRef = grappleSelfRef
        local owner = grappleOwnerRef
        if not selfRef or not owner then
            return
        end

        flying = true

        pcall(function()
            realSelfStates = selfRef.states
            selfRef.states = setmetatable({__real_states = realSelfStates}, statesProxyMt)
        end)

        pcall(function()
            realOwnerStates = owner.states
            owner.states = setmetatable({__real_states = realOwnerStates}, ownerStatesProxyMt)
        end)

        pcall(function()
            local humanoid = owner.instance:FindFirstChildOfClass("Humanoid")
            if humanoid then
                trackedHumanoid = humanoid
                oldWalkspeed = humanoid.WalkSpeed
                oldJumppower = humanoid.JumpPower
                humanoid.WalkSpeed = 0
                humanoid.JumpPower = 0
            end
        end)

        pcall(function()
            if selfRef.move_position then
                selfRef.move_position.MaxVelocity = M.pullSpeed
                selfRef.move_position.Responsiveness = 10
            end
        end)

        local root = owner.instance:FindFirstChild("HumanoidRootPart")
        local currentTarget = root and root.Position or camera.CFrame.Position

        pcall(function()
            local stayCf = CFrame.new(currentTarget)
            selfRef:start_rappel_mode(owner, stayCf, stayCf)
        end)

        flyConnection = RunService.Heartbeat:Connect(newcclosure(function(dt)
            if not flying then
                return
            end

            local dir = getWasdDirection()
            if dir.Magnitude > 0 then
                local checkRoot = owner.instance:FindFirstChild("HumanoidRootPart")
                if checkRoot then
                    local toTarget = currentTarget - checkRoot.Position
                    if toTarget.Magnitude < 3 or dir.Magnitude > 0 then
                        currentTarget = currentTarget + dir * M.speed * dt
                    end
                end
            end

            pcall(function()
                if selfRef.move_position then
                    selfRef.move_position.Position = currentTarget
                end
            end)
        end))
    end

    local function installHooks()
        if hooksReady then
            return
        end

        local okRequire, grapple = pcall(function()
            return require(ReplicatedStorage.Modules.Items.Item.Utility.GrapplingHook)
        end)
        if not okRequire or not grapple then
            warn("[Op1Nibbler] RappelFly: failed to require GrapplingHook module")
            return
        end

        GrappleModule = grapple

        local hookfunction = hookfunction or function(f)
            return f
        end

        local oldGpcs
        oldGpcs = hookfunction(game.GetPropertyChangedSignal, newcclosure(function(self, property)
            if flying and self == trackedHumanoid then
                if property == "WalkSpeed" or property == "JumpPower" then
                    return dummyEvent.Event
                end
            end
            return oldGpcs(self, property)
        end))

        local oldHookInputs = clonefunc(GrappleModule.hook_inputs)
        GrappleModule.hook_inputs = newcclosure(function(selfRef, ...)
            grappleSelfRef = selfRef
            grappleOwnerRef = selfRef.owner
            return oldHookInputs(selfRef, ...)
        end)

        local oldCanRappel = clonefunc(GrappleModule.can_rappel)
        GrappleModule.can_rappel = newcclosure(function(selfRef, owner)
            if not flying then
                return oldCanRappel(selfRef, owner)
            end

            local target = camera.CFrame.Position + camera.CFrame.LookVector * 100
            return CFrame.new(target), CFrame.new(target + Vector3.new(0, 2, 0))
        end)

        local oldStartRappel = clonefunc(GrappleModule.start_rappel_mode)
        replaceclosure(GrappleModule.start_rappel_mode, newcclosure(function(selfRef, owner, ...)
            return oldStartRappel(selfRef, owner, ...)
        end))

        hooksReady = true
    end

    function M:Init()
        if initialized then
            return
        end
        initialized = true

        installHooks()

        inputConnection = UserInputService.InputBegan:Connect(newcclosure(function(input, processed)
            if processed or not M.enabled then
                return
            end

            if input.KeyCode == M.flyKey then
                if flying then
                    stopFlying()
                elseif grappleSelfRef and grappleOwnerRef then
                    startFlying()
                end
            end
        end))

        LocalPlayer.CharacterRemoving:Connect(newcclosure(function(char)
            if not flying then
                return
            end

            local humanoid = char:FindFirstChildOfClass("Humanoid")
            local root = char:FindFirstChild("HumanoidRootPart")
            if humanoid and root and root.Parent then
                humanoid.WalkSpeed = oldWalkspeed or 16
                humanoid.JumpPower = oldJumppower or 50
            end
            stopFlying()
        end))
    end

    function M:SetEnabled(state)
        self.enabled = state and true or false
        if self.enabled and not initialized then
            self:Init()
        end
        if not self.enabled and flying then
            stopFlying()
        end
    end

    function M:SetSpeed(value)
        self.speed = tonumber(value) or self.speed
    end

    function M:SetPullSpeed(value)
        self.pullSpeed = tonumber(value) or self.pullSpeed
        if flying and grappleSelfRef and grappleSelfRef.move_position then
            grappleSelfRef.move_position.MaxVelocity = self.pullSpeed
        end
    end

    return M
end
