return function(ctx)
    local cloneref = cloneref or function(obj)
        return obj
    end
    local newcclosure = newcclosure or function(fn)
        return fn
    end

    local Workspace = (ctx and ctx.Services and ctx.Services.Workspace) or cloneref(game:GetService("Workspace"))
    local RunService = (ctx and ctx.Services and ctx.Services.RunService) or cloneref(game:GetService("RunService"))
    local Players = cloneref(game:GetService("Players"))
    local LocalPlayer = Players.LocalPlayer

    local M = {
        enabled = false,
        noSmoke = true,
        noFlash = true
    }

    local initialized = false
    local smokeConnection = nil
    local flashDescAddedConnection = nil
    local flashPlayerGuiConnection = nil
    local flashHeartbeatConnection = nil
    local flashSweepTimer = 0

    local modifiedParts = {}
    local modifiedEmitters = {}

    local function getPlayerGui()
        if not LocalPlayer then
            return nil
        end
        return LocalPlayer:FindFirstChildOfClass("PlayerGui")
    end

    local function isFlashLike(instance)
        if not instance or typeof(instance) ~= "Instance" then
            return false
        end
        local name = string.lower(instance.Name or "")
        return name == "flash" or string.find(name, "flash", 1, true) ~= nil
    end

    local function suppressFlashGui(instance)
        pcall(function()
            if instance:IsA("ScreenGui") then
                instance.Enabled = false
            end
        end)
        pcall(function()
            if instance:IsA("GuiObject") then
                instance.Visible = false
            end
        end)
    end

    local function applyNoFlash(root)
        if not root or not (M.enabled and M.noFlash) then
            return
        end

        if isFlashLike(root) then
            suppressFlashGui(root)
        end

        for _, desc in ipairs(root:GetDescendants()) do
            if isFlashLike(desc) then
                suppressFlashGui(desc)
            end
        end
    end

    local function applyPart(part)
        if modifiedParts[part] then
            return
        end
        modifiedParts[part] = {
            LocalTransparencyModifier = part.LocalTransparencyModifier,
            Size = part.Size
        }
        part.LocalTransparencyModifier = 1
        part.Size = Vector3.new(0.001, 0.001, 0.001)
    end

    local function restorePart(part)
        local original = modifiedParts[part]
        if not original then
            return
        end
        if part and part.Parent then
            part.LocalTransparencyModifier = original.LocalTransparencyModifier
            part.Size = original.Size
        end
        modifiedParts[part] = nil
    end

    local function applyEmitter(emitter)
        if modifiedEmitters[emitter] ~= nil then
            return
        end
        modifiedEmitters[emitter] = emitter.Enabled
        emitter.Enabled = false
    end

    local function restoreEmitter(emitter)
        local original = modifiedEmitters[emitter]
        if original == nil then
            return
        end
        if emitter and emitter.Parent then
            emitter.Enabled = original
        end
        modifiedEmitters[emitter] = nil
    end

    local function visitSmokeObject(obj, apply)
        pcall(function()
            if obj:IsA("BasePart") then
                if apply then
                    applyPart(obj)
                else
                    restorePart(obj)
                end
            end

            for _, part in ipairs(obj:GetDescendants()) do
                if part:IsA("BasePart") then
                    if apply then
                        applyPart(part)
                    else
                        restorePart(part)
                    end
                elseif part:IsA("ParticleEmitter") or part:IsA("Smoke") then
                    if apply then
                        applyEmitter(part)
                    else
                        restoreEmitter(part)
                    end
                end
            end
        end)
    end

    local function refreshSmoke()
        local shouldApply = M.enabled and M.noSmoke

        for _, obj in ipairs(Workspace:GetChildren()) do
            if obj.Name == "SmokePart" then
                visitSmokeObject(obj, shouldApply)
            end
        end

        if not shouldApply then
            for part in pairs(modifiedParts) do
                restorePart(part)
            end
            for emitter in pairs(modifiedEmitters) do
                restoreEmitter(emitter)
            end
        end
    end

    local function refreshFlash()
        if not (M.enabled and M.noFlash) then
            return
        end
        local playerGui = getPlayerGui()
        if playerGui then
            applyNoFlash(playerGui)
        end
    end

    function M:Init()
        if initialized then
            return
        end
        initialized = true

        smokeConnection = Workspace.ChildAdded:Connect(newcclosure(function(obj)
            if obj.Name == "SmokePart" and M.enabled and M.noSmoke then
                visitSmokeObject(obj, true)
            end
        end))

        local function bindFlashWatcher()
            if flashDescAddedConnection then
                flashDescAddedConnection:Disconnect()
                flashDescAddedConnection = nil
            end

            local playerGui = getPlayerGui()
            if not playerGui then
                return
            end

            flashDescAddedConnection = playerGui.DescendantAdded:Connect(newcclosure(function(instance)
                if M.enabled and M.noFlash and isFlashLike(instance) then
                    suppressFlashGui(instance)
                end
            end))
        end

        bindFlashWatcher()

        flashPlayerGuiConnection = LocalPlayer.ChildAdded:Connect(newcclosure(function(child)
            if child:IsA("PlayerGui") then
                bindFlashWatcher()
                refreshFlash()
            end
        end))

        local hookmetamethod = hookmetamethod
        if hookmetamethod then
            local oldNewIndex
            oldNewIndex = hookmetamethod(game, "__newindex", newcclosure(function(self, key, value)
                if M.enabled and M.noFlash and (key == "Enabled" or key == "Visible") and typeof(self) == "Instance" then
                    local playerGui = getPlayerGui()
                    if playerGui and self:IsDescendantOf(playerGui) and isFlashLike(self) then
                        return
                    end
                end
                return oldNewIndex(self, key, value)
            end))
        end

        flashHeartbeatConnection = RunService.Heartbeat:Connect(newcclosure(function(dt)
            if not (M.enabled and M.noFlash) then
                return
            end
            flashSweepTimer = flashSweepTimer + dt
            if flashSweepTimer >= 0.2 then
                flashSweepTimer = 0
                refreshFlash()
            end
        end))

        refreshSmoke()
        refreshFlash()
    end

    function M:SetEnabled(state)
        self.enabled = state and true or false
        if self.enabled and not initialized then
            self:Init()
        end
        refreshSmoke()
        refreshFlash()
    end

    function M:SetNoSmoke(state)
        self.noSmoke = state and true or false
        refreshSmoke()
    end

    function M:SetNoFlash(state)
        self.noFlash = state and true or false
        refreshFlash()
    end

    return M
end
