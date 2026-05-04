--[[
	AutoCircle — Deathball Auto-Hit
	FxckingAngel/Explore

	Draws a 30-stud ring around your character.
	When the Deathball enters your ring, auto-triggers F instantly.
	The ball also gets its own tracking ring so you can see it.
	
	loadstring(game:HttpGet("https://raw.githubusercontent.com/FxckingAngel/Explore/refs/heads/main/Scripts/AutoCircle.lua"))()
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")

local plr = Players.LocalPlayer

-- ── Config ────────────────────────────────────────────────────────────────────
local RADIUS       = 30     -- your detection ring radius (studs)
local SEGMENTS     = 64     -- ring smoothness
local BAND         = 6      -- extra tolerance (radius ± studs)
local COOLDOWN     = 0.2    -- min seconds between triggers on same ball
local DEBUG        = true   -- print what gets triggered

-- Colors
local RING_IDLE    = Color3.fromRGB(0, 180, 255)
local RING_HOT     = Color3.fromRGB(255, 50, 50)
local BALL_RING_C  = Color3.fromRGB(255, 200, 0)

-- ── Human Logic ───────────────────────────────────────────────────────────────
-- Deathball context:
--   - Ball gets FASTER every hit (pressure builds)
--   - Player moves themselves (no movement injection)
--   - Reaction must tighten as ball speeds up (or you die)
--   - Occasional late/miss is human — but less so at high speed (panic mode)
--   - Fatigue: long rallies make you slightly slower then you recover
local HUMAN = {
	-- Reaction time at LOW ball speed (slow ball = relaxed, ~200-350ms)
	ReactionSlow    = {min=0.18, max=0.34},

	-- Reaction time at HIGH ball speed (fast ball = panic, ~120-200ms)
	-- Ball speed threshold where panic kicks in (studs/s)
	PanicSpeed      = 60,
	ReactionFast    = {min=0.11, max=0.21},

	-- Miss chance at low speed (8%) — drops toward 0 as ball gets fast
	-- At panic speed: miss chance = 0 (you HAVE to hit it)
	MissChanceSlow  = 0.08,

	-- Jitter: tiny random noise on each reaction (feels organic)
	JitterMax       = 0.05,

	-- Fatigue: builds over a long rally, slightly slows reaction
	FatiguePerHit   = 0.003,   -- adds ~3ms per hit
	FatigueMax      = 0.06,    -- cap at +60ms
	FatigueDecay    = 0.002,   -- recovers 2ms per second idle

	-- Post-hit ignore: don't re-trigger immediately after a hit
	PostHitIgnore   = 0.35,
}

-- ── Human State ───────────────────────────────────────────────────────────────
local humanState = {
	fatigue     = 0,
	hitCount    = 0,
	lastHitTime = 0,
	postIgnore  = 0,
	pending     = false,
}

local function rng(min, max)
	return min + math.random() * (max - min)
end

local function getReactionTime(ballSpeed)
	-- Lerp between slow and fast reaction based on ball speed
	local t = math.clamp((ballSpeed - 20) / (HUMAN.PanicSpeed - 20), 0, 1)
	local rMin = HUMAN.ReactionSlow.min + (HUMAN.ReactionFast.min - HUMAN.ReactionSlow.min) * t
	local rMax = HUMAN.ReactionSlow.max + (HUMAN.ReactionFast.max - HUMAN.ReactionSlow.max) * t
	local reaction = rng(rMin, rMax)

	-- Add jitter (organic micro-variance)
	reaction = reaction + rng(0, HUMAN.JitterMax)

	-- Add fatigue
	reaction = reaction + humanState.fatigue

	return reaction
end

local function getMissChance(ballSpeed)
	-- Miss chance shrinks as ball gets faster — panic = no misses
	local t = math.clamp((ballSpeed - 20) / (HUMAN.PanicSpeed - 20), 0, 1)
	return HUMAN.MissChanceSlow * (1 - t)
end

-- ── Ball detection ────────────────────────────────────────────────────────────
-- Deathball game: ball is usually named "Ball", "DeathBall", "Sphere" etc
-- We detect it by: spherical shape, unanchored, moving, NOT a player part
local BALL_NAMES = {
	"ball", "deathball", "death_ball", "sphere", "projectile",
	"puck", "orb", "boulder", "rock", "bomb",
}

local function looksLikeBall(obj)
	if not obj:IsA("BasePart") then return false end
	if obj.Anchored then return false end

	-- Check name match
	local name = obj.Name:lower()
	for _, n in pairs(BALL_NAMES) do
		if name == n or name:find(n) then return true end
	end

	-- Check shape: sphere or roughly equal XYZ size
	if obj:IsA("Part") then
		if obj.Shape == Enum.PartType.Ball then return true end
		local s = obj.Size
		local ratio = math.max(s.X,s.Y,s.Z) / math.max(0.01, math.min(s.X,s.Y,s.Z))
		if ratio < 1.5 and s.X > 1 then return true end  -- roughly spherical
	end

	-- Check if it has a ball-like mesh
	local mesh = obj:FindFirstChildWhichIsA("SpecialMesh")
	if mesh and mesh.MeshType == Enum.MeshType.Sphere then return true end

	return false
end

local function isPlayerPart(obj)
	for _, p in pairs(Players:GetPlayers()) do
		local c = p.Character
		if c and obj:IsDescendantOf(c) then return true end
	end
	return false
end

-- Find the ball in workspace
local function findBall()
	-- First try by name
	for _, obj in pairs(workspace:GetDescendants()) do
		if not isPlayerPart(obj) and looksLikeBall(obj) then
			return obj
		end
	end
	return nil
end

-- ── State ─────────────────────────────────────────────────────────────────────
local active      = false
local myRing      = {}      -- your detection ring parts
local ballRing    = {}      -- ball tracking ring parts
local lastTrigger = 0
local renderConn  = nil

local ringFolder  = Instance.new("Folder")
ringFolder.Name   = "_AutoCircle"
ringFolder.Parent = workspace

-- ── Ring ──────────────────────────────────────────────────────────────────────
local function makeRing(radius, color, height)
	local parts = {}
	local step  = (2 * math.pi) / SEGMENTS
	for i = 0, SEGMENTS - 1 do
		local a  = i * step
		local b  = (i + 1) * step
		local ax, az = math.cos(a), math.sin(a)
		local bx, bz = math.cos(b), math.sin(b)
		local cx, cz = (ax+bx)/2, (az+bz)/2
		local len = Vector3.new((bx-ax)*radius, 0, (bz-az)*radius).Magnitude
		local p = Instance.new("Part")
		p.Anchored     = true
		p.CanCollide   = false
		p.CanQuery     = false
		p.CanTouch     = false
		p.CastShadow   = false
		p.Size         = Vector3.new(len+0.05, height or 0.3, 0.3)
		p.Color        = color
		p.Material     = Enum.Material.Neon
		p.Transparency = 0.2
		p.Parent       = ringFolder
		parts[i+1]     = p
	end
	return parts
end

local function positionRing(parts, origin, radius, yOff)
	local step = (2 * math.pi) / SEGMENTS
	for i, p in pairs(parts) do
		local a  = (i-1)*step
		local b  = i*step
		local ax, az = math.cos(a), math.sin(a)
		local bx, bz = math.cos(b), math.sin(b)
		local cx, cz = (ax+bx)/2, (az+bz)/2
		p.CFrame = CFrame.new(
			origin.X + cx*radius,
			origin.Y + (yOff or 0),
			origin.Z + cz*radius
		) * CFrame.Angles(0, -math.atan2(bz-az, bx-ax), 0)
	end
end

local function colorRing(parts, col)
	for _, p in pairs(parts) do p.Color = col end
end

local function destroyRing(parts)
	for _, p in pairs(parts) do pcall(p.Destroy, p) end
end

-- ── Trigger ───────────────────────────────────────────────────────────────────
local function doHit(ball)
	if not ball or not ball.Parent then return end
	local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local speed = ball.AssemblyLinearVelocity.Magnitude

	if DEBUG then
		print(("[AutoCircle] HIT  speed=%.0f  reaction=~%.0fms  fatigue=%.0fms  hits=%d"):format(
			speed,
			getReactionTime(speed) * 1000,
			humanState.fatigue * 1000,
			humanState.hitCount
		))
	end

	-- firetouchinterest — simulate contact
	pcall(firetouchinterest, root, ball, 0)
	pcall(firetouchinterest, ball, root, 0)
	task.wait(rng(0.03, 0.06))
	pcall(firetouchinterest, root, ball, 1)
	pcall(firetouchinterest, ball, root, 1)

	-- ClickDetector if present
	local click = ball:FindFirstChildWhichIsA("ClickDetector", true)
	if not click then
		local m = ball:FindFirstAncestorWhichIsA("Model")
		if m then click = m:FindFirstChildWhichIsA("ClickDetector", true) end
	end
	if click then pcall(fireclickdetector, click) end

	-- F key with human hold time
	pcall(function()
		game:GetService("VirtualInputManager"):SendKeyEvent(true,  Enum.KeyCode.F, false, game)
		task.wait(rng(0.05, 0.11))  -- human key hold duration varies
		game:GetService("VirtualInputManager"):SendKeyEvent(false, Enum.KeyCode.F, false, game)
	end)

	-- Update state
	humanState.hitCount    = humanState.hitCount + 1
	humanState.lastHitTime = tick()
	humanState.postIgnore  = tick() + HUMAN.PostHitIgnore
	humanState.fatigue     = math.min(humanState.fatigue + HUMAN.FatiguePerHit, HUMAN.FatigueMax)
end

local function triggerF(ball)
	local now = tick()
	if now - lastTrigger < COOLDOWN then return end
	if humanState.pending then return end
	if humanState.postIgnore > now then return end
	lastTrigger = now

	local speed = ball.AssemblyLinearVelocity.Magnitude

	-- Miss check — fast ball = almost never miss, slow ball = sometimes miss
	local missChance = getMissChance(speed)
	if math.random() < missChance then
		if DEBUG then
			print(("[AutoCircle] MISS (%.0f%% chance at speed=%.0f)"):format(missChance*100, speed))
		end
		return
	end

	-- Human reaction delay — tightens as ball speeds up
	local delay = getReactionTime(speed)
	humanState.pending = true

	task.delay(delay, function()
		humanState.pending = false
		-- Recover fatigue while idle between hits
		local idleTime = tick() - humanState.lastHitTime
		humanState.fatigue = math.max(0, humanState.fatigue - HUMAN.FatigueDecay * idleTime)
		doHit(ball)
	end)
end

-- ── Main loop ─────────────────────────────────────────────────────────────────
local function getRoot()
	local c = plr.Character
	return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChildWhichIsA("BasePart"))
end

local cachedBall = nil
local ballSearchTick = 0

local function update()
	local root = getRoot()
	if not root then return end
	local origin = root.Position

	-- Reposition your ring
	positionRing(myRing, origin, RADIUS)

	-- Find ball (re-search every 0.5s)
	local now = tick()
	if not cachedBall or not cachedBall.Parent or now - ballSearchTick > 0.5 then
		cachedBall = findBall()
		ballSearchTick = now
	end
	local ball = cachedBall

	-- Reposition ball ring
	if ball and ball.Parent then
		if #ballRing == 0 then
			ballRing = makeRing(ball.Size.Magnitude * 0.8, BALL_RING_C, 0.25)
		end
		local ballOrigin = Vector3.new(ball.Position.X, root.Position.Y, ball.Position.Z)
		positionRing(ballRing, ballOrigin, ball.Size.Magnitude * 0.8)
	else
		if #ballRing > 0 then
			destroyRing(ballRing)
			ballRing = {}
		end
	end

	-- Check if ball is in your ring
	if ball and ball.Parent then
		local flatDist = Vector3.new(
			ball.Position.X - origin.X,
			0,
			ball.Position.Z - origin.Z
		).Magnitude

		if flatDist <= RADIUS + BAND then
			colorRing(myRing, RING_HOT)
			triggerF(ball)
		else
			colorRing(myRing, RING_IDLE)
		end
	else
		colorRing(myRing, RING_IDLE)
	end
end

-- ── Enable / Disable ──────────────────────────────────────────────────────────
local function enable()
	if active then return end
	active     = true
	cachedBall = nil
	myRing     = makeRing(RADIUS, RING_IDLE)
	renderConn = RunService.Heartbeat:Connect(update)
	print("[AutoCircle] ON — searching for ball...")
end

local function disable()
	if not active then return end
	active = false
	if renderConn then renderConn:Disconnect() renderConn = nil end
	destroyRing(myRing) myRing = {}
	destroyRing(ballRing) ballRing = {}
	cachedBall = nil
	print("[AutoCircle] OFF")
end

-- ── UI ────────────────────────────────────────────────────────────────────────
-- Clean up old instance
for _, holder in pairs({game:GetService("CoreGui"), plr.PlayerGui}) do
	local old = holder:FindFirstChild("AutoCircleUI")
	if old then old:Destroy() end
end

local gui = Instance.new("ScreenGui")
gui.Name          = "AutoCircleUI"
gui.ResetOnSpawn  = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.DisplayOrder  = 9999

local frame = Instance.new("Frame", gui)
frame.Size             = UDim2.new(0, 210, 0, 90)
frame.Position         = UDim2.new(0.5, -105, 0, 20)
frame.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
frame.BorderSizePixel  = 0
frame.Active           = true
Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke", frame)
stroke.Color     = RING_IDLE
stroke.Thickness = 1.5

local title = Instance.new("TextLabel", frame)
title.Text             = "⬤  DEATHBALL AUTO-HIT"
title.Font             = Enum.Font.GothamBold
title.TextSize         = 12
title.TextColor3       = RING_IDLE
title.BackgroundTransparency = 1
title.Position         = UDim2.new(0, 12, 0, 8)
title.Size             = UDim2.new(1, -24, 0, 16)
title.TextXAlignment   = Enum.TextXAlignment.Left

local sub = Instance.new("TextLabel", frame)
sub.Text             = "Ring: " .. RADIUS .. " studs  |  Auto-hits ball on contact"
sub.Font             = Enum.Font.Gotham
sub.TextSize         = 10
sub.TextColor3       = Color3.fromRGB(100, 100, 100)
sub.BackgroundTransparency = 1
sub.Position         = UDim2.new(0, 12, 0, 26)
sub.Size             = UDim2.new(1, -24, 0, 14)
sub.TextXAlignment   = Enum.TextXAlignment.Left

local ballStatus = Instance.new("TextLabel", frame)
ballStatus.Text             = "Ball: searching..."
ballStatus.Font             = Enum.Font.Gotham
ballStatus.TextSize         = 10
ballStatus.TextColor3       = Color3.fromRGB(120, 120, 120)
ballStatus.BackgroundTransparency = 1
ballStatus.Position         = UDim2.new(0, 12, 0, 42)
ballStatus.Size             = UDim2.new(1, -24, 0, 14)
ballStatus.TextXAlignment   = Enum.TextXAlignment.Left

local btn = Instance.new("TextButton", frame)
btn.Text             = "OFF"
btn.Font             = Enum.Font.GothamBold
btn.TextSize         = 13
btn.TextColor3       = Color3.fromRGB(255,255,255)
btn.BackgroundColor3 = Color3.fromRGB(45,45,45)
btn.BorderSizePixel  = 0
btn.AutoButtonColor  = false
btn.Position         = UDim2.new(1,-74, 0.5,-16)
btn.Size             = UDim2.new(0,62,0,32)
Instance.new("UICorner", btn).CornerRadius = UDim.new(0,8)

local ti = TweenInfo.new(0.15, Enum.EasingStyle.Quad)

local function updateBtn()
	if active then
		TweenService:Create(btn,   ti, {BackgroundColor3=Color3.fromRGB(0,160,80)}):Play()
		TweenService:Create(stroke,ti, {Color=RING_HOT}):Play()
		TweenService:Create(title, ti, {TextColor3=RING_HOT}):Play()
		btn.Text = "ON"
	else
		TweenService:Create(btn,   ti, {BackgroundColor3=Color3.fromRGB(45,45,45)}):Play()
		TweenService:Create(stroke,ti, {Color=RING_IDLE}):Play()
		TweenService:Create(title, ti, {TextColor3=RING_IDLE}):Play()
		btn.Text = "OFF"
	end
end

btn.MouseButton1Click:Connect(function()
	if active then disable() else enable() end
	updateBtn()
end)
btn.MouseEnter:Connect(function()
	TweenService:Create(btn,ti,{BackgroundColor3=active and Color3.fromRGB(0,200,100) or Color3.fromRGB(65,65,65)}):Play()
end)
btn.MouseLeave:Connect(function()
	TweenService:Create(btn,ti,{BackgroundColor3=active and Color3.fromRGB(0,160,80) or Color3.fromRGB(45,45,45)}):Play()
end)

-- Update ball status label
RunService.Heartbeat:Connect(function()
	if not active then return end
	if cachedBall and cachedBall.Parent then
		ballStatus.Text      = "Ball: " .. cachedBall.Name .. " ✓"
		ballStatus.TextColor3 = Color3.fromRGB(0,200,100)
	else
		ballStatus.Text       = "Ball: searching..."
		ballStatus.TextColor3 = Color3.fromRGB(180,100,0)
	end
end)

-- Drag
local dragging, dragStart, startPos
frame.InputBegan:Connect(function(i)
	if i.UserInputType == Enum.UserInputType.MouseButton1 then
		dragging=true dragStart=i.Position startPos=frame.Position
	end
end)
UserInputService.InputChanged:Connect(function(i)
	if dragging and i.UserInputType==Enum.UserInputType.MouseMovement then
		local d=i.Position-dragStart
		frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
	end
end)
UserInputService.InputEnded:Connect(function(i)
	if i.UserInputType==Enum.UserInputType.MouseButton1 then dragging=false end
end)

-- Respawn
plr.CharacterAdded:Connect(function()
	if active then
		disable() task.wait(1) enable() updateBtn()
	end
end)

local ok = pcall(function() game:GetService("CoreGui"):GetFullName() end)
gui.Parent = ok and game:GetService("CoreGui") or plr.PlayerGui

print("[AutoCircle] Deathball Auto-Hit loaded.")
print("[AutoCircle] Click ON — blue ring = your zone, yellow ring = ball tracking")
print("[AutoCircle] Ball enters your ring -> F triggered instantly")
