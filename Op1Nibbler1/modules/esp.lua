return function(ctx)
    local RunService = ctx.Services.RunService
    local Workspace = ctx.Services.Workspace

    local M = {
        initialized = false,
        enabled = false,
        teamCheck = true,
        playerBoxEnabled = true,
        objectBoxEnabled = true,
        playerColor = Color3.fromRGB(210, 50, 80),
        droneColor = Color3.fromRGB(0, 255, 255),
        claymoreColor = Color3.fromRGB(255, 0, 0),
        proximityColor = Color3.fromRGB(255, 165, 0),
        stickyColor = Color3.fromRGB(255, 192, 203),
        playerThickness = 2,
        objectThickness = 1.5,
        playerTransparency = 1,
        objectTransparency = 0.9,
        teamCache = {},
        lastCache = 0,
        cacheInterval = 0.7,
        playerBoxes = {},
        objectBoxes = {},
        connections = {}
    }

    local camera = Workspace.CurrentCamera
    local corners = table.create(8)
    local points = table.create(8)
    for i = 1, 8 do
        corners[i] = Vector3.new()
        points[i] = Vector3.new()
    end

    local function disconnectAll(list)
        for _, c in ipairs(list) do
            pcall(function() c:Disconnect() end)
        end
        table.clear(list)
    end

    local function isOnScreen(pos)
        local _, onScreen = camera:WorldToViewportPoint(pos)
        return onScreen
    end

    local function isInFrustum(pos)
        local relative = pos - camera.CFrame.Position
        local look = camera.CFrame.LookVector
        if relative:Dot(look) <= 0 then
            return false
        end
        local angle = math.acos(math.min(1, relative.Unit:Dot(look)))
        return angle < math.rad(60)
    end

    function M:UpdateTeamCache()
        self.teamCache = {}
        for _, v in ipairs(Workspace:GetChildren()) do
            if v:IsA("Highlight") and v.Adornee then
                self.teamCache[v.Adornee] = true
            end
        end
        self.lastCache = tick()
    end

    function M:IsTeammate(model)
        if not self.teamCheck then
            return false
        end
        if tick() - self.lastCache > self.cacheInterval then
            self:UpdateTeamCache()
        end
        return self.teamCache[model] == true
    end

    function M:ApplyPlayerStyle(box)
        box.Thickness = self.playerThickness
        box.Transparency = self.playerTransparency
        box.Color = self.playerColor
    end

    function M:ApplyObjectStyle(box, objectName)
        box.Thickness = self.objectThickness
        box.Transparency = self.objectTransparency
        if objectName == "Drone" then
            box.Color = self.droneColor
        elseif objectName == "Claymore" then
            box.Color = self.claymoreColor
        elseif objectName == "ProximityAlarm" then
            box.Color = self.proximityColor
        elseif objectName == "StickyCamera" then
            box.Color = self.stickyColor
        end
    end

    function M:RefreshStyles()
        for _, data in pairs(self.playerBoxes) do
            self:ApplyPlayerStyle(data.box)
        end
        for model, data in pairs(self.objectBoxes) do
            self:ApplyObjectStyle(data.box, model.Name)
        end
    end

    function M:GetPlayerBox(data)
        local head, torso = data.head, data.torso
        if not head or not torso or not data.isVisible then
            return nil
        end
        if not isInFrustum(torso.Position) or not isOnScreen(torso.Position) then
            return nil
        end

        local hsx, hsy = head.Size.X / 2, head.Size.Y / 2
        local tsx, tsy = torso.Size.X / 2, torso.Size.Y / 2
        points[1] = head.Position + Vector3.new(-hsx, hsy, 0)
        points[2] = head.Position + Vector3.new(hsx, hsy, 0)
        points[3] = torso.Position + Vector3.new(-tsx, -tsy, 0)
        points[4] = torso.Position + Vector3.new(tsx, -tsy, 0)

        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
        local any = false

        for i = 1, 4 do
            local screenPos, onScreen = camera:WorldToViewportPoint(points[i])
            if onScreen then
                any = true
                minX = math.min(minX, screenPos.X)
                minY = math.min(minY, screenPos.Y)
                maxX = math.max(maxX, screenPos.X)
                maxY = math.max(maxY, screenPos.Y)
            end
        end

        if not any then
            return nil
        end

        local p = 3
        return Vector2.new(minX - p, minY - p), Vector2.new((maxX - minX) + p * 2, (maxY - minY) + p * 2)
    end

    function M:GetObjectBox(model)
        local cf, size = model:GetBoundingBox()
        if not isInFrustum(cf.Position) or not isOnScreen(cf.Position) then
            return nil
        end

        local halfX, halfY, halfZ = size.X / 2, size.Y / 2, size.Z / 2
        corners[1] = cf * Vector3.new(-halfX, -halfY, -halfZ)
        corners[2] = cf * Vector3.new(-halfX, -halfY, halfZ)
        corners[3] = cf * Vector3.new(-halfX, halfY, -halfZ)
        corners[4] = cf * Vector3.new(-halfX, halfY, halfZ)
        corners[5] = cf * Vector3.new(halfX, -halfY, -halfZ)
        corners[6] = cf * Vector3.new(halfX, -halfY, halfZ)
        corners[7] = cf * Vector3.new(halfX, halfY, -halfZ)
        corners[8] = cf * Vector3.new(halfX, halfY, halfZ)

        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
        local any = false

        for i = 1, 8 do
            local screenPos, onScreen = camera:WorldToViewportPoint(corners[i])
            if onScreen then
                any = true
                minX = math.min(minX, screenPos.X)
                minY = math.min(minY, screenPos.Y)
                maxX = math.max(maxX, screenPos.X)
                maxY = math.max(maxY, screenPos.Y)
            end
        end

        if not any then
            return nil
        end

        return Vector2.new(minX, minY), Vector2.new(maxX - minX, maxY - minY)
    end

    function M:CreatePlayerBox(char)
        if self.playerBoxes[char] or char.Name == "LocalViewmodel" then
            return
        end
        local head = char:FindFirstChild("head")
        local torso = char:FindFirstChild("torso")
        if not head or not torso then
            return
        end

        local box = Drawing.new("Square")
        box.Visible, box.Filled, box.ZIndex = false, false, 2
        self:ApplyPlayerStyle(box)

        local data = {
            box = box,
            head = head,
            torso = torso,
            isVisible = torso.Transparency <= 0.95,
            conns = {}
        }
        self.playerBoxes[char] = data

        table.insert(data.conns, head:GetPropertyChangedSignal("Transparency"):Connect(function()
            local d = self.playerBoxes[char]
            if d then d.isVisible = d.torso.Transparency <= 0.95 end
        end))
        table.insert(data.conns, torso:GetPropertyChangedSignal("Transparency"):Connect(function()
            local d = self.playerBoxes[char]
            if d then d.isVisible = d.torso.Transparency <= 0.95 end
        end))
        table.insert(data.conns, char.AncestryChanged:Connect(function(_, parent)
            if not parent then
                self:RemovePlayerBox(char)
            end
        end))
    end

    function M:RemovePlayerBox(char)
        local data = self.playerBoxes[char]
        if not data then
            return
        end
        disconnectAll(data.conns)
        pcall(function() data.box:Remove() end)
        self.playerBoxes[char] = nil
    end

    function M:CreateObjectBox(model)
        if self.objectBoxes[model] then
            return
        end
        if model.Name ~= "Drone" and model.Name ~= "Claymore" and model.Name ~= "ProximityAlarm" and model.Name ~= "StickyCamera" then
            return
        end

        local box = Drawing.new("Square")
        box.Visible, box.Filled, box.ZIndex = false, false, 3
        self:ApplyObjectStyle(box, model.Name)

        local data = { box = box, conns = {} }
        self.objectBoxes[model] = data

        table.insert(data.conns, model.AncestryChanged:Connect(function(_, parent)
            if not parent then
                self:RemoveObjectBox(model)
            end
        end))
    end

    function M:RemoveObjectBox(model)
        local data = self.objectBoxes[model]
        if not data then
            return
        end
        disconnectAll(data.conns)
        pcall(function() data.box:Remove() end)
        self.objectBoxes[model] = nil
    end

    function M:SetEnabled(state)
        self.enabled = state and true or false
    end

    function M:Init()
        if self.initialized then
            return
        end

        local vmFolder = Workspace:FindFirstChild("Viewmodels") or Workspace:WaitForChild("Viewmodels", 10)
        if vmFolder then
            for _, model in ipairs(vmFolder:GetChildren()) do
                if model:IsA("Model") and model.Name ~= "LocalViewmodel" then
                    self:CreatePlayerBox(model)
                end
            end
            table.insert(self.connections, vmFolder.ChildAdded:Connect(function(model)
                if model:IsA("Model") and model.Name ~= "LocalViewmodel" then
                    task.delay(0.25, function()
                        self:CreatePlayerBox(model)
                    end)
                end
            end))
        end

        for _, child in ipairs(Workspace:GetChildren()) do
            self:CreateObjectBox(child)
        end
        table.insert(self.connections, Workspace.ChildAdded:Connect(function(child)
            self:CreateObjectBox(child)
        end))

        table.insert(self.connections, RunService.RenderStepped:Connect(function()
            if not self.enabled then
                for _, data in pairs(self.playerBoxes) do data.box.Visible = false end
                for _, data in pairs(self.objectBoxes) do data.box.Visible = false end
                return
            end

            if tick() - self.lastCache > self.cacheInterval then
                self:UpdateTeamCache()
            end

            if self.playerBoxEnabled then
                for char, data in pairs(self.playerBoxes) do
                    if char:IsDescendantOf(Workspace) then
                        if self:IsTeammate(char) then
                            data.box.Visible = false
                        else
                            local position, size = self:GetPlayerBox(data)
                            if position and size then
                                data.box.Position = position
                                data.box.Size = size
                                data.box.Visible = true
                            else
                                data.box.Visible = false
                            end
                        end
                    else
                        self:RemovePlayerBox(char)
                    end
                end
            else
                for _, data in pairs(self.playerBoxes) do data.box.Visible = false end
            end

            if self.objectBoxEnabled then
                for model, data in pairs(self.objectBoxes) do
                    if model:IsDescendantOf(Workspace) then
                        local position, size = self:GetObjectBox(model)
                        if position and size then
                            data.box.Position = position
                            data.box.Size = size
                            data.box.Visible = true
                        else
                            data.box.Visible = false
                        end
                    else
                        self:RemoveObjectBox(model)
                    end
                end
            else
                for _, data in pairs(self.objectBoxes) do data.box.Visible = false end
            end
        end))

        self.initialized = true
    end

    return M
end
