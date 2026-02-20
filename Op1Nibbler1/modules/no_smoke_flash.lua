return function(ctx)
    local Runtime = ctx and ctx.Runtime or {}
    local cloneref = Runtime.cloneref or cloneref or function(obj)
        return obj
    end
    local newcclosure = Runtime.newcclosure or newcclosure or function(fn)
        return fn
    end
    local hookfunction = Runtime.hookfunction or hookfunction or function(f)
        return f
    end
    local Instance_new = Runtime.InstanceNew or cloneref(Instance.new)

    local Services = ctx and ctx.Services or {}
    local Workspace = Services.Workspace or cloneref(game:GetService("Workspace"))
    local Players = Services.Players or cloneref(game:GetService("Players"))
    local LocalPlayer = Players.LocalPlayer

    local M = {
        enabled = false,
        noSmoke = true,
        noFlash = true
    }

    local initialized = false
    local smokeConnection = nil
    local flashDescAddedConnection = nil
    local flashDescRemovingConnection = nil
    local flashPlayerGuiConnection = nil

    local modifiedParts = {}
    local modifiedEmitters = {}
    local trackedFlashInstances = {}
    local spoofedSmokeInstances = {}
    local spoofedFlashInstances = {}
    local dummySignalEvent = Instance_new("BindableEvent")
    local flashHookTarget = nil
    local flashNewIndexHookInstalled = false
    local oldFlashNewIndex = nil

    local oldGetPropertyChangedSignal
    oldGetPropertyChangedSignal = hookfunction(game.GetPropertyChangedSignal, newcclosure(function(self, property)
        local shouldBlock = (spoofedSmokeInstances[self] and M.enabled and M.noSmoke) or
                                (spoofedFlashInstances[self] and M.enabled and M.noFlash)
        if shouldBlock and (property == "Size" or property == "Transparency" or property == "LocalTransparencyModifier" or
            property == "Color" or property == "Enabled" or property == "Visible") then
            return dummySignalEvent.Event
        end
        return oldGetPropertyChangedSignal(self, property)
    end))

    local function ensureFlashNewIndexSpoof(target)
        local hookmetamethod = Runtime.hookmetamethod or hookmetamethod
        if not hookmetamethod or not target then
            return
        end

        flashHookTarget = target
        if flashNewIndexHookInstalled then
            return
        end

        oldFlashNewIndex = hookmetamethod(target, "__newindex", newcclosure(function(self, key, value)
            if self == flashHookTarget and M.enabled and M.noFlash and key == "Enabled" then
                return
            end
            return oldFlashNewIndex(self, key, value)
        end))
        flashNewIndexHookInstalled = true
    end

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
        spoofedFlashInstances[instance] = true
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

    local function clearTrackedFlash(instance)
        local tracked = trackedFlashInstances[instance]
        if not tracked then
            return
        end

        if tracked.enabledConnection then
            tracked.enabledConnection:Disconnect()
        end
        if tracked.visibleConnection then
            tracked.visibleConnection:Disconnect()
        end
        if tracked.ancestryConnection then
            tracked.ancestryConnection:Disconnect()
        end

        spoofedFlashInstances[instance] = nil
        trackedFlashInstances[instance] = nil
    end

    local function trackFlashInstance(instance)
        if not isFlashLike(instance) then
            return
        end

        if trackedFlashInstances[instance] then
            if M.enabled and M.noFlash then
                suppressFlashGui(instance)
            end
            return
        end

        local tracked = {}
        trackedFlashInstances[instance] = tracked
        spoofedFlashInstances[instance] = true
        if instance.Name == "Flash" then
            ensureFlashNewIndexSpoof(instance)
        end

        tracked.ancestryConnection = instance.AncestryChanged:Connect(newcclosure(function(_, parent)
            if not parent then
                clearTrackedFlash(instance)
                return
            end

            if M.enabled and M.noFlash then
                suppressFlashGui(instance)
            end
        end))

        pcall(function()
            tracked.enabledConnection = instance:GetPropertyChangedSignal("Enabled"):Connect(newcclosure(function()
                if M.enabled and M.noFlash and instance.Parent and instance.Enabled then
                    instance.Enabled = false
                end
            end))
        end)

        pcall(function()
            tracked.visibleConnection = instance:GetPropertyChangedSignal("Visible"):Connect(newcclosure(function()
                if M.enabled and M.noFlash and instance.Parent and instance.Visible then
                    instance.Visible = false
                end
            end))
        end)

        if M.enabled and M.noFlash then
            suppressFlashGui(instance)
        end
    end

    local function applyNoFlash(root)
        if not root or not (M.enabled and M.noFlash) then
            return
        end

        if isFlashLike(root) then
            trackFlashInstance(root)
        end

        for _, desc in ipairs(root:GetDescendants()) do
            if isFlashLike(desc) then
                trackFlashInstance(desc)
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
        spoofedSmokeInstances[part] = true
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
        spoofedSmokeInstances[part] = nil
        modifiedParts[part] = nil
    end

    local function applyEmitter(emitter)
        if modifiedEmitters[emitter] ~= nil then
            return
        end
        modifiedEmitters[emitter] = emitter.Enabled
        spoofedSmokeInstances[emitter] = true
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
        spoofedSmokeInstances[emitter] = nil
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
            local exactFlash = playerGui:FindFirstChild("Flash")
            if exactFlash then
                ensureFlashNewIndexSpoof(exactFlash)
                trackFlashInstance(exactFlash)
                suppressFlashGui(exactFlash)
            end
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
            if flashDescRemovingConnection then
                flashDescRemovingConnection:Disconnect()
                flashDescRemovingConnection = nil
            end

            for instance in pairs(trackedFlashInstances) do
                clearTrackedFlash(instance)
            end

            local playerGui = getPlayerGui()
            if not playerGui then
                return
            end

            flashDescAddedConnection = playerGui.DescendantAdded:Connect(newcclosure(function(instance)
                if M.enabled and M.noFlash and isFlashLike(instance) then
                    trackFlashInstance(instance)
                end
            end))

            flashDescRemovingConnection = playerGui.DescendantRemoving:Connect(newcclosure(function(instance)
                if trackedFlashInstances[instance] then
                    clearTrackedFlash(instance)
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
