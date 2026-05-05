--[[
	AutoDeflect v35 — Deathball Velocity Detection
	FxckingAngel/Explore

	Watches ball velocity direction every frame.
	When ball is aimed at YOU (dot product toward your position),
	fires deflect immediately — before ball even gets close.
	No ring needed. Earlier detection = deflect before you get hit.

	loadstring(game:HttpGet("https://raw.githubusercontent.com/FxckingAngel/Explore/main/Scripts/Load.lua"))()
]]

-- Kill old instance
if _G._AutoDeflectCleanup then pcall(_G._AutoDeflectCleanup) _G._AutoDeflectCleanup = nil end
do
	local old = workspace:FindFirstChild("_AutoDeflect")
	if old then old:Destroy() end
	for _, h in pairs({game:GetService("CoreGui"), game:GetService("Players").LocalPlayer.PlayerGui}) do
		local g = h:FindFirstChild("AutoDeflectUI")
		if g then g:Destroy() end
	end
end
task.wait(0.1)

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local VIM              = game:GetService("VirtualInputManager")
local plr              = Players.LocalPlayer

-- ── Config ────────────────────────────────────────────────────────────────────
local MAX_DIST     = 60    -- only care about ball within 60 studs
local AIM_DOT      = 0.7   -- how directly aimed at us (0.7 = within ~45 degrees)
local MIN_SPEED    = 15    -- ignore slow/stationary ball
local REFIRE_CD    = 0.6   -- min seconds between deflects
local SEGMENTS     = 48    -- ring smoothness

local RING_IDLE = Color3.fromRGB(0, 180, 255)
local RING_HOT  = Color3.fromRGB(255, 50, 50)
local BALL_COL  = Color3.fromRGB(255, 200, 0)

-- ── State ─────────────────────────────────────────────────────────────────────
local active      = false
local myRing      = {}
local ballRing    = {}
local cachedBall  = nil
local lastFired   = 0
local deflectBtn  = nil
local renderConn  = nil

local ringFolder  = Instance.new("Folder")
ringFolder.Name   = "_AutoDeflect"
ringFolder.Parent = workspace

-- ── Ring ──────────────────────────────────────────────────────────────────────
local function makeRing(radius, color)
	local parts = {}
	local step  = (2 * math.pi) / SEGMENTS
	for i = 0, SEGMENTS - 1 do
		local a  = i * step
		local b  = (i+1) * step
		local ax, az = math.cos(a), math.sin(a)
		local bx, bz = math.cos(b), math.sin(b)
		local cx, cz = (ax+bx)/2, (az+bz)/2
		local len = Vector3.new((bx-ax)*radius,0,(bz-az)*radius).Magnitude
		local p = Instance.new("Part")
		p.Anchored=true p.CanCollide=false p.CanQuery=false
		p.CanTouch=false p.CastShadow=false
		p.Size=Vector3.new(len+0.05,0.3,0.3)
		p.Color=color p.Material=Enum.Material.Neon
		p.Transparency=0.2 p.Parent=ringFolder
		parts[i+1]=p
	end
	return parts
end

local function posRing(parts, origin, radius)
	local step = (2*math.pi)/SEGMENTS
	for i,p in pairs(parts) do
		local a=(i-1)*step local b=i*step
		local ax,az=math.cos(a),math.sin(a)
		local bx,bz=math.cos(b),math.sin(b)
		local cx,cz=(ax+bx)/2,(az+bz)/2
		p.CFrame=CFrame.new(origin.X+cx*radius,origin.Y,origin.Z+cz*radius)
			*CFrame.Angles(0,-math.atan2(bz-az,bx-ax),0)
	end
end

local function colorRing(parts, col)
	for _,p in pairs(parts) do p.Color=col end
end

local function destroyRing(parts)
	for _,p in pairs(parts) do pcall(p.Destroy,p) end
end

local function getRoot()
	local c=plr.Character
	return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChildWhichIsA("BasePart"))
end

-- ── Ball detection ────────────────────────────────────────────────────────────
local function watchFX(fx)
	local rock = fx:FindFirstChild("RockTemplate")
	if rock then cachedBall = rock end
	fx.ChildAdded:Connect(function(child)
		if child.Name == "RockTemplate" then cachedBall = child end
	end)
	fx.ChildRemoved:Connect(function(child)
		if child.Name == "RockTemplate" and cachedBall == child then cachedBall = nil end
	end)
end
local _fx = workspace:FindFirstChild("FX")
if _fx then watchFX(_fx) end
workspace.ChildAdded:Connect(function(c) if c.Name == "FX" then watchFX(c) end end)

-- ── Deflect ───────────────────────────────────────────────────────────────────
local function getDeflectButton()
	for _, v in pairs(plr.PlayerGui:GetDescendants()) do
		if v.Name == "DeflectButton" and v:IsA("GuiButton") then return v end
	end
	return nil
end

local function pressDeflect()
	if not deflectBtn or not deflectBtn.Parent then
		deflectBtn = getDeflectButton()
	end
	if deflectBtn then
		pcall(function()
			local conn = deflectBtn.MouseButton1Click:Connect(function() end)
			conn:Disconnect()
			deflectBtn.MouseButton1Click:Fire()
		end)
	end
	pcall(VIM.SendKeyEvent, VIM, true,  Enum.KeyCode.F, false, game)
	pcall(VIM.SendKeyEvent, VIM, false, Enum.KeyCode.F, false, game)
end

-- ── Main update ───────────────────────────────────────────────────────────────
local DISPLAY_RADIUS = 8  -- visual ring around player (small, just for reference)

local function update()
	local root = getRoot()
	if not root then return end
	local origin = root.Position

	-- Position display ring
	posRing(myRing, origin, DISPLAY_RADIUS)

	-- Fallback ball search
	if not cachedBall or not cachedBall.Parent then
		local fx = workspace:FindFirstChild("FX")
		if fx then
			local rock = fx:FindFirstChild("RockTemplate")
			if rock then cachedBall = rock end
		end
	end

	local ball = cachedBall

	-- Ball tracking ring
	if ball and ball.Parent then
		if #ballRing == 0 then ballRing = makeRing(3, BALL_COL) end
		posRing(ballRing, Vector3.new(ball.Position.X, origin.Y, ball.Position.Z), 3)
	elseif #ballRing > 0 then
		destroyRing(ballRing) ballRing = {}
	end

	if not ball or not ball.Parent then
		colorRing(myRing, RING_IDLE)
		return
	end

	local ballPos   = ball.Position
	local ballVel   = ball.AssemblyLinearVelocity
	local speed     = ballVel.Magnitude
	local dist      = (Vector3.new(ballPos.X, origin.Y, ballPos.Z) - origin).Magnitude

	-- Direction from ball to us
	local toPlayer  = (Vector3.new(origin.X, ballPos.Y, origin.Z) - ballPos)
	local toPlayerFlat = Vector3.new(toPlayer.X, 0, toPlayer.Z)
	local velFlat   = Vector3.new(ballVel.X, 0, ballVel.Z)

	-- Is ball aimed at us?
	local aimedAtUs = false
	if speed >= MIN_SPEED and dist <= MAX_DIST and velFlat.Magnitude > 1 and toPlayerFlat.Magnitude > 0 then
		local dot = velFlat.Unit:Dot(toPlayerFlat.Unit)
		aimedAtUs = dot >= AIM_DOT
	end

	-- Are we the closest player to the ball? (don't deflect if someone else is closer)
	local weAreClosest = true
	for _, p in pairs(Players:GetPlayers()) do
		if p ~= plr and p.Character then
			local otherRoot = p.Character:FindFirstChild("HumanoidRootPart")
			if otherRoot then
				local otherDist = (Vector3.new(ballPos.X, otherRoot.Position.Y, ballPos.Z) - otherRoot.Position).Magnitude
				if otherDist < dist - 3 then  -- they're more than 3 studs closer
					weAreClosest = false
					break
				end
			end
		end
	end

	if aimedAtUs and weAreClosest then
		colorRing(myRing, RING_HOT)
		local now = tick()
		if now - lastFired >= REFIRE_CD then
			lastFired = now
			-- Fire deflect - ball is coming at us from dist studs away
			task.spawn(function()
				pressDeflect()
				task.wait(0.06)
				pressDeflect()
				task.wait(0.06)
				pressDeflect()
			end)
		end
	else
		colorRing(myRing, RING_IDLE)
	end
end

-- ── Enable / Disable ──────────────────────────────────────────────────────────
local function enable()
	if active then return end
	active = true
	myRing = makeRing(DISPLAY_RADIUS, RING_IDLE)
	deflectBtn = getDeflectButton()
	renderConn = RunService.Heartbeat:Connect(update)
end

local function disable()
	if not active then return end
	active = false
	if renderConn then renderConn:Disconnect() renderConn = nil end
	destroyRing(myRing) myRing = {}
	destroyRing(ballRing) ballRing = {}
end

-- ── UI ────────────────────────────────────────────────────────────────────────
local gui = Instance.new("ScreenGui")
gui.Name="AutoDeflectUI" gui.ResetOnSpawn=false
gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling gui.DisplayOrder=9999

local frame = Instance.new("Frame", gui)
frame.Size=UDim2.new(0,220,0,86) frame.Position=UDim2.new(0.5,-110,0,20)
frame.BackgroundColor3=Color3.fromRGB(12,12,12) frame.BorderSizePixel=0
frame.Active=true
Instance.new("UICorner",frame).CornerRadius=UDim.new(0,12)

local stroke=Instance.new("UIStroke",frame)
stroke.Color=RING_IDLE stroke.Thickness=1.5

local title=Instance.new("TextLabel",frame)
title.Text="⬤  AUTO-DEFLECT  v35"
title.Font=Enum.Font.GothamBold title.TextSize=12
title.TextColor3=RING_IDLE title.BackgroundTransparency=1
title.Position=UDim2.new(0,12,0,8) title.Size=UDim2.new(1,-80,0,16)
title.TextXAlignment=Enum.TextXAlignment.Left

local sub=Instance.new("TextLabel",frame)
sub.Text="Velocity detection — fires before ball arrives"
sub.Font=Enum.Font.Gotham sub.TextSize=10
sub.TextColor3=Color3.fromRGB(100,100,100) sub.BackgroundTransparency=1
sub.Position=UDim2.new(0,12,0,26) sub.Size=UDim2.new(1,-24,0,14)
sub.TextXAlignment=Enum.TextXAlignment.Left

local ballStatus=Instance.new("TextLabel",frame)
ballStatus.Font=Enum.Font.Gotham ballStatus.TextSize=10
ballStatus.TextColor3=Color3.fromRGB(100,100,100) ballStatus.BackgroundTransparency=1
ballStatus.Position=UDim2.new(0,12,0,42) ballStatus.Size=UDim2.new(1,-24,0,14)
ballStatus.TextXAlignment=Enum.TextXAlignment.Left

local btn=Instance.new("TextButton",frame)
btn.Text="OFF" btn.Font=Enum.Font.GothamBold btn.TextSize=13
btn.TextColor3=Color3.fromRGB(255,255,255)
btn.BackgroundColor3=Color3.fromRGB(45,45,45)
btn.BorderSizePixel=0 btn.AutoButtonColor=false
btn.Position=UDim2.new(1,-72,0,8) btn.Size=UDim2.new(0,60,0,28)
Instance.new("UICorner",btn).CornerRadius=UDim.new(0,8)

local ti=TweenInfo.new(0.15,Enum.EasingStyle.Quad)
local function updateBtn()
	if active then
		TweenService:Create(btn,ti,{BackgroundColor3=Color3.fromRGB(0,160,80)}):Play()
		TweenService:Create(stroke,ti,{Color=RING_HOT}):Play()
		btn.Text="ON"
	else
		TweenService:Create(btn,ti,{BackgroundColor3=Color3.fromRGB(45,45,45)}):Play()
		TweenService:Create(stroke,ti,{Color=RING_IDLE}):Play()
		btn.Text="OFF"
	end
end

btn.MouseButton1Click:Connect(function()
	if active then disable() else enable() end
	updateBtn()
end)

-- Status
RunService.Heartbeat:Connect(function()
	if not active then ballStatus.Text="Inactive" return end
	local ball = cachedBall
	if ball and ball.Parent then
		local root = getRoot()
		local dist = root and math.floor((Vector3.new(ball.Position.X, root.Position.Y, ball.Position.Z) - root.Position).Magnitude) or 0
		local spd = math.floor(ball.AssemblyLinearVelocity.Magnitude)
		ballStatus.Text = "Ball: "..dist.."s  "..spd.."v  "..(tick()-lastFired < 0.1 and "DEFLECT!" or "")
		ballStatus.TextColor3 = tick()-lastFired < 0.3 and Color3.fromRGB(255,80,80) or Color3.fromRGB(0,200,100)
	else
		ballStatus.Text="Ball: searching..."
		ballStatus.TextColor3=Color3.fromRGB(180,100,0)
	end
end)

-- Drag
local drag,ds,sp
frame.InputBegan:Connect(function(i)
	if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=true ds=i.Position sp=frame.Position end
end)
UserInputService.InputChanged:Connect(function(i)
	if drag and i.UserInputType==Enum.UserInputType.MouseMovement then
		local d=i.Position-ds
		frame.Position=UDim2.new(sp.X.Scale,sp.X.Offset+d.X,sp.Y.Scale,sp.Y.Offset+d.Y)
	end
end)
UserInputService.InputEnded:Connect(function(i)
	if i.UserInputType==Enum.UserInputType.MouseButton1 then drag=false end
end)

plr.CharacterAdded:Connect(function()
	if active then disable() task.wait(1) enable() updateBtn() end
end)

_G._AutoDeflectCleanup = function()
	disable()
	pcall(gui.Destroy,gui)
	pcall(ringFolder.Destroy,ringFolder)
end

local ok=pcall(function() game:GetService("CoreGui"):GetFullName() end)
gui.Parent=ok and game:GetService("CoreGui") or plr.PlayerGui

print("[AutoDeflect] v35 loaded - velocity direction detection")
print("[AutoDeflect] Fires when ball aimed at you from up to "..MAX_DIST.." studs away")
