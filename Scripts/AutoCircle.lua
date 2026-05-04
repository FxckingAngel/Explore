--[[
	AutoCircle — FxckingAngel/Explore
	
	Draws a 30-stud ring around your character.
	When ANY object enters the ring, it auto-presses F on it instantly.
	UI to toggle on/off. Draggable.
	
	loadstring(game:HttpGet("https://raw.githubusercontent.com/FxckingAngel/Explore/refs/heads/main/Scripts/AutoCircle.lua"))()
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")

local plr  = Players.LocalPlayer
local char = plr.Character or plr.CharacterAdded:Wait()

-- ── Config ────────────────────────────────────────────────────────────────────
local RADIUS      = 30        -- stud radius of ring
local SEGMENTS    = 80        -- ring smoothness
local RING_COLOR  = Color3.fromRGB(0, 200, 255)
local HIT_COLOR   = Color3.fromRGB(255, 60, 60)
local BAND        = 4         -- how close to radius edge counts as "touching"
local COOLDOWN    = 0.1       -- seconds between auto-presses per object

-- ── State ─────────────────────────────────────────────────────────────────────
local active     = false
local ringParts  = {}
local ringFolder = Instance.new("Folder")
ringFolder.Name  = "_AutoCircle"
ringFolder.Parent = workspace

local triggered  = {}   -- [obj] = last tick it was triggered
local renderConn = nil

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function getRoot()
	local c = plr.Character
	if not c then return nil end
	return c:FindFirstChild("HumanoidRootPart") or c:FindFirstChildWhichIsA("BasePart")
end

local function isCharPart(obj)
	local c = plr.Character
	return c and obj:IsDescendantOf(c)
end

-- ── Ring build ────────────────────────────────────────────────────────────────
local function buildRing()
	for _, p in pairs(ringParts) do p:Destroy() end
	ringParts = {}
	local step = (2 * math.pi) / SEGMENTS
	for i = 0, SEGMENTS - 1 do
		local a  = i * step
		local b  = (i + 1) * step
		local ax, az = math.cos(a), math.sin(a)
		local bx, bz = math.cos(b), math.sin(b)
		local cx, cz = (ax+bx)/2, (az+bz)/2
		local len = Vector3.new((bx-ax)*RADIUS, 0, (bz-az)*RADIUS).Magnitude

		local p = Instance.new("Part")
		p.Anchored     = true
		p.CanCollide   = false
		p.CanQuery     = false
		p.CanTouch     = false
		p.CastShadow   = false
		p.Size         = Vector3.new(len + 0.05, 0.3, 0.4)
		p.Color        = RING_COLOR
		p.Material     = Enum.Material.Neon
		p.Transparency = 0.25
		p.Parent       = ringFolder
		ringParts[i+1] = p
	end
end

local function destroyRing()
	for _, p in pairs(ringParts) do p:Destroy() end
	ringParts = {}
end

local function colorRing(col)
	for _, p in pairs(ringParts) do p.Color = col end
end

-- ── Auto-press F ─────────────────────────────────────────────────────────────
local function pressF(obj)
	-- Simulate F key via ContextActionService
	local fakeInput = {
		KeyCode     = Enum.KeyCode.F,
		UserInputType = Enum.UserInputType.Keyboard,
		UserInputState = Enum.UserInputState.Begin,
	}
	-- Fire the game's own input handlers
	local vip = Instance.new("VirtualInputManager")
	pcall(function()
		game:GetService("VirtualInputManager"):SendKeyEvent(true, Enum.KeyCode.F, false, game)
	end)

	-- Also use ContextActionService to bind & fire
	-- And directly call game's tool/touch functions
	pcall(function()
		-- If it's a tool, equip it
		if obj:IsA("Tool") then
			plr.Character.Humanoid:EquipTool(obj)
		end
	end)

	-- Fire touch on the object toward the character
	pcall(function()
		if obj:IsA("BasePart") then
			local root = getRoot()
			if root then
				-- simulate touch event
				firetouchinterest(root, obj, 0)
				firetouchinterest(root, obj, 1)
			end
		end
	end)

	print("[AutoCircle] Auto-triggered: " .. obj:GetFullName())
end

-- ── Main update loop ──────────────────────────────────────────────────────────
local function update()
	local root = getRoot()
	if not root then return end
	local origin = root.Position
	local step   = (2 * math.pi) / SEGMENTS
	local now    = tick()
	local anyHit = false

	-- Move ring
	for i, p in pairs(ringParts) do
		local a  = (i-1)*step
		local b  = i*step
		local ax, az = math.cos(a), math.sin(a)
		local bx, bz = math.cos(b), math.sin(b)
		local cx, cz = (ax+bx)/2, (az+bz)/2
		p.CFrame = CFrame.new(
			origin.X + cx*RADIUS,
			origin.Y,
			origin.Z + cz*RADIUS
		) * CFrame.Angles(0, -math.atan2(bz-az, bx-ax), 0)
	end

	-- Build a set of all player character parts to ignore
	local playerParts = {}
	for _, p in pairs(Players:GetPlayers()) do
		if p.Character then
			for _, v in pairs(p.Character:GetDescendants()) do
				playerParts[v] = true
			end
			playerParts[p.Character] = true
		end
	end

	-- Names/classes that are clearly floor/terrain/map geometry to skip
	local function isEnvironment(obj)
		-- Skip terrain
		if obj:IsA("Terrain") then return true end
		-- Skip anything anchored with a flat/large surface (floor-like)
		if obj.Anchored then
			local size = obj.Size
			-- Large flat part = floor/wall/ceiling
			if (size.X > 20 or size.Z > 20) and size.Y < 5 then return true end
			if (size.X > 20 or size.Z > 20) and size.X > 20 then return true end
		end
		-- Skip by common environment names
		local name = obj.Name:lower()
		local envNames = {
			"floor","ground","wall","ceiling","base","platform","spawn",
			"map","terrain","baseplate","part","road","path","boundary",
			"border","barrier","invisible","hitbox","region","zone",
		}
		for _, n in pairs(envNames) do
			if name == n or name:find(n) then return true end
		end
		return false
	end

	local function shouldTrigger(obj)
		-- Must be a BasePart
		if not obj:IsA("BasePart") then return false end
		-- Skip ring parts
		if obj.Parent == ringFolder then return false end
		-- Skip our own character
		if isCharPart(obj) then return false end
		-- Skip all other players and their characters
		if playerParts[obj] then return false end
		-- Skip environment/map geometry
		if isEnvironment(obj) then return false end
		-- Must be moving (not anchored) OR be a Tool/model that makes sense to trigger
		if obj.Anchored and not obj:FindFirstAncestorWhichIsA("Tool") then return false end
		return true
	end

	-- Scan for objects crossing the ring band
	for _, obj in pairs(workspace:GetDescendants()) do
		if shouldTrigger(obj) then
			local flatPos = Vector3.new(obj.Position.X, origin.Y, obj.Position.Z)
			local dist    = (flatPos - origin).Magnitude

			-- Crossing ring band OR fully inside
			if dist <= RADIUS + BAND then
				anyHit = true
				local cooldownTime = dist >= RADIUS - BAND and COOLDOWN or 1
				if not triggered[obj] or (now - triggered[obj]) >= cooldownTime then
					triggered[obj] = now
					pressF(obj)
				end
			end
		end
	end

	-- Clean up triggered table for objects that left
	for obj, _ in pairs(triggered) do
		if not obj or not obj.Parent then
			triggered[obj] = nil
		end
	end

	colorRing(anyHit and HIT_COLOR or RING_COLOR)
end

-- ── Toggle ────────────────────────────────────────────────────────────────────
local function enable()
	if active then return end
	active = true
	triggered = {}
	buildRing()
	renderConn = RunService.Heartbeat:Connect(update)
	print("[AutoCircle] ON — radius: " .. RADIUS .. " studs")
end

local function disable()
	if not active then return end
	active = false
	if renderConn then renderConn:Disconnect() renderConn = nil end
	destroyRing()
	triggered = {}
	print("[AutoCircle] OFF")
end

-- ── UI ────────────────────────────────────────────────────────────────────────
-- Remove old UI if re-executed
pcall(function()
	local old = (game:GetService("CoreGui"):FindFirstChild("AutoCircleUI"))
		or (plr.PlayerGui:FindFirstChild("AutoCircleUI"))
	if old then old:Destroy() end
end)

local gui = Instance.new("ScreenGui")
gui.Name          = "AutoCircleUI"
gui.ResetOnSpawn  = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder  = 9999

-- Frame
local frame = Instance.new("Frame", gui)
frame.Size              = UDim2.new(0, 200, 0, 80)
frame.Position          = UDim2.new(0.5, -100, 0, 20)
frame.BackgroundColor3  = Color3.fromRGB(15, 15, 15)
frame.BorderSizePixel   = 0
frame.Active            = true
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke", frame)
stroke.Color     = Color3.fromRGB(0, 200, 255)
stroke.Thickness = 1.5
stroke.Transparency = 0.4

-- Title
local title = Instance.new("TextLabel", frame)
title.Text              = "⬤  AUTO CIRCLE"
title.Font              = Enum.Font.GothamBold
title.TextSize          = 13
title.TextColor3        = Color3.fromRGB(0, 200, 255)
title.BackgroundTransparency = 1
title.Position          = UDim2.new(0, 12, 0, 8)
title.Size              = UDim2.new(1, -24, 0, 18)
title.TextXAlignment    = Enum.TextXAlignment.Left

-- Status label
local statusLabel = Instance.new("TextLabel", frame)
statusLabel.Text         = "Objects auto-triggered on contact"
statusLabel.Font         = Enum.Font.Gotham
statusLabel.TextSize     = 10
statusLabel.TextColor3   = Color3.fromRGB(120, 120, 120)
statusLabel.BackgroundTransparency = 1
statusLabel.Position     = UDim2.new(0, 12, 0, 28)
statusLabel.Size         = UDim2.new(1, -24, 0, 14)
statusLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Radius label
local radLabel = Instance.new("TextLabel", frame)
radLabel.Text         = "Radius: " .. RADIUS .. " studs"
radLabel.Font         = Enum.Font.Gotham
radLabel.TextSize     = 10
radLabel.TextColor3   = Color3.fromRGB(80, 80, 80)
radLabel.BackgroundTransparency = 1
radLabel.Position     = UDim2.new(0, 12, 1, -22)
radLabel.Size         = UDim2.new(0, 120, 0, 14)
radLabel.TextXAlignment = Enum.TextXAlignment.Left

-- Toggle button
local btn = Instance.new("TextButton", frame)
btn.Text             = "OFF"
btn.Font             = Enum.Font.GothamBold
btn.TextSize         = 13
btn.TextColor3       = Color3.fromRGB(255,255,255)
btn.BackgroundColor3 = Color3.fromRGB(50,50,50)
btn.BorderSizePixel  = 0
btn.AutoButtonColor  = false
btn.Position         = UDim2.new(1, -74, 0.5, -16)
btn.Size             = UDim2.new(0, 62, 0, 32)
Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

local ti = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function updateBtn()
	if active then
		TweenService:Create(btn, ti, {BackgroundColor3 = Color3.fromRGB(0,180,80)}):Play()
		TweenService:Create(stroke, ti, {Color = HIT_COLOR}):Play()
		btn.Text = "ON"
		statusLabel.TextColor3 = Color3.fromRGB(0,200,100)
	else
		TweenService:Create(btn, ti, {BackgroundColor3 = Color3.fromRGB(50,50,50)}):Play()
		TweenService:Create(stroke, ti, {Color = Color3.fromRGB(0,200,255)}):Play()
		btn.Text = "OFF"
		statusLabel.TextColor3 = Color3.fromRGB(120,120,120)
	end
end

btn.MouseButton1Click:Connect(function()
	if active then disable() else enable() end
	updateBtn()
end)

btn.MouseEnter:Connect(function()
	TweenService:Create(btn, ti, {BackgroundColor3 = active and Color3.fromRGB(0,220,100) or Color3.fromRGB(70,70,70)}):Play()
end)
btn.MouseLeave:Connect(function()
	TweenService:Create(btn, ti, {BackgroundColor3 = active and Color3.fromRGB(0,180,80) or Color3.fromRGB(50,50,50)}):Play()
end)

-- Drag
local dragging, dragStart, startPos
frame.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging  = true
		dragStart = input.Position
		startPos  = frame.Position
	end
end)
UserInputService.InputChanged:Connect(function(input)
	if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
		local d = input.Position - dragStart
		frame.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + d.X,
			startPos.Y.Scale, startPos.Y.Offset + d.Y
		)
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
end)

-- Inject
local holder = pcall(function() game:GetService("CoreGui"):GetFullName() end)
	and game:GetService("CoreGui") or plr.PlayerGui
gui.Parent = holder

-- Respawn: rebuild ring if character dies
plr.CharacterAdded:Connect(function(newChar)
	char = newChar
	if active then
		disable()
		task.wait(1)
		enable()
		updateBtn()
	end
end)

print("[AutoCircle] Ready. Click ON to activate.")
print("[AutoCircle] Ring radius: " .. RADIUS .. " studs")
print("[AutoCircle] Objects that enter the ring are auto-triggered instantly.")
