--[[
	ScriptViewer App Module
	
	Enhanced script viewer with multi-strategy decompiler.
	Tries every known executor decompile API in priority order,
	with graceful fallback and diagnostic output.
]]

-- Common Locals
local Main,Lib,Apps,Settings
local Explorer, Properties, ScriptViewer, Notebook
local API,RMD,env,service,plr,create,createSimple

local function initDeps(data)
	Main = data.Main
	Lib = data.Lib
	Apps = data.Apps
	Settings = data.Settings
	API = data.API
	RMD = data.RMD
	env = data.env
	service = data.service
	plr = data.plr
	create = data.create
	createSimple = data.createSimple
end

local function initAfterMain()
	Explorer = Apps.Explorer
	Properties = Apps.Properties
	ScriptViewer = Apps.ScriptViewer
	Notebook = Apps.Notebook
end

local function main()
	local ScriptViewer = {}
	local window, codeFrame
	local bridgeRemote
	local liveEditEnabled = false
	local currentScript

	-- ============================================================
	-- Constants
	-- ============================================================

	local MAX_DISPLAY_BYTES = 512 * 1024 -- 512 KB; larger sources freeze the UI

	-- ============================================================
	-- Decompiler Core
	-- ============================================================

	--[[
	STRATEGY ORDER
	==============
	1. decompile(script)             Standard global — Synapse X, KRNL, Fluxus
	2. syn.decompile(script)         Synapse X legacy namespace
	3. decompiler.decompile(script)  Some custom executors
	4. _G.decompile(script)          Executors that inject via _G
	5. getscriptbytecode(script)     Last resort — not readable but confirms bytecode exists

	Each strategy is wrapped in pcall. A broken executor API never crashes the viewer.
	--]]

	local function tryStrategy(name, fn, scr)
		local ok, result = pcall(fn, scr)
		if not ok then
			return nil, ("'%s' errored: %s"):format(name, tostring(result))
		end
		if type(result) ~= "string" then
			return nil, ("'%s' returned %s, not string"):format(name, type(result))
		end
		if #result == 0 then
			return nil, ("'%s' returned empty string"):format(name)
		end
		local lowered = string.lower(result)
		if lowered:find("<!doctype html", 1, true)
			or lowered:find("<html", 1, true)
			or lowered:find("cloudfront", 1, true)
			or lowered:find("request could not be satisfied", 1, true)
			or lowered:find("konstant api", 1, true)
		then
			return nil, ("'%s' returned remote HTML/error payload"):format(name)
		end
		return result, nil
	end

	local function buildMetadataBlock(scr)
		local fullName = "unknown"
		pcall(function() fullName = scr:GetFullName() end)

		local runCtx = "N/A"
		pcall(function() runCtx = tostring(scr.RunContext) end)

		return table.concat({
			"--[[",
			"  Dex Script Viewer — Source Unavailable",
			"  ----------------------------------------",
			("  Name:       %s"):format(tostring(scr.Name)),
			("  ClassName:  %s"):format(tostring(scr.ClassName)),
			("  FullName:   %s"):format(fullName),
			("  Disabled:   %s"):format(tostring(scr.Disabled)),
			("  RunContext: %s"):format(runCtx),
			"",
			"  The source could not be retrieved. Common causes:",
			"    1. Your executor does not support decompilation",
			"    2. The script uses Luau bytecode with no readable source",
			"    3. The game uses server-side script protection",
			"    4. The script object is sandboxed from the decompiler",
			"--]]",
			"",
		}, "\n")
	end

	local function buildStrategies()
		return {
			{
				name = "decompiler.decompile()",
				fn = function(s)
					assert(
						type(decompiler) == "table" and type(decompiler.decompile) == "function",
						"not available"
					)
					return decompiler.decompile(s)
				end,
			},
			{
				name = "syn.decompile()",
				fn = function(s)
					assert(type(syn) == "table" and type(syn.decompile) == "function", "not available")
					return syn.decompile(s)
				end,
			},
			{
				name = "getrenv().decompile()",
				fn = function(s)
					assert(type(getrenv) == "function", "not available")
					local renv = getrenv()
					assert(type(renv) == "table" and type(renv.decompile) == "function", "not available")
					return renv.decompile(s)
				end,
			},
			{
				name = "decompile()",
				fn = function(s)
					assert(type(decompile) == "function", "not available")
					return decompile(s)
				end,
			},
			{
				name = "getscriptclosure() + decompile()",
				fn = function(s)
					assert(type(getscriptclosure) == "function", "not available")
					local cl = getscriptclosure(s)
					assert(type(cl) == "function", "no closure")
					local dec = decompile or (_G and _G.decompile)
					assert(type(dec) == "function", "decompile not available")
					return dec(cl)
				end,
			},
			{
				name = "_G.decompile()",
				fn = function(s)
					local fn = _G.decompile
					assert(type(fn) == "function", "not available")
					return fn(s)
				end,
			},
			{
				-- NOTE: getscriptbytecode returns raw bytecode, not Lua source.
				-- We wrap it in a comment block so the viewer shows something useful.
				name = "getscriptbytecode()",
				fn = function(s)
					assert(type(getscriptbytecode) == "function", "not available")
					local bc = getscriptbytecode(s)
					assert(type(bc) == "string" and #bc > 0, "empty bytecode")
					return table.concat({
						"--[[ Bytecode only — no decompiler available or all failed.",
						("     Script:        %s (%s)"):format(tostring(s.Name), tostring(s.ClassName)),
						("     Bytecode size: %d bytes"):format(#bc),
						"     Use Synapse X or KRNL for readable source output.",
						"--]]",
					}, "\n")
				end,
			},
		}
	end

	-- Master decompile — always returns a display-ready string, never nil or error.
	local function decompileScript(scr)
		local strategies = buildStrategies()
		local failReasons = {}

		for _, strategy in ipairs(strategies) do
			local source, reason = tryStrategy(strategy.name, strategy.fn, scr)
			if source then
				-- Guard against output that would freeze the CodeFrame UI
				if #source > MAX_DISPLAY_BYTES then
					source = source:sub(1, MAX_DISPLAY_BYTES) ..
						("\n\n--[[ Truncated at %d KB — full source exceeds display limit ]]"):format(
							MAX_DISPLAY_BYTES // 1024
						)
				end
				-- Prepend a brief header so the user knows which strategy succeeded
				return ("-- Decompiled via: %s\n-- Script: %s (%s)\n\n"):format(
					strategy.name,
					tostring(scr.Name),
					tostring(scr.ClassName)
				) .. source
			end
			table.insert(failReasons, reason)
		end

		-- All strategies failed — build a useful diagnostic block
		local lines = { buildMetadataBlock(scr), "--[[ Diagnostic — all strategies failed: ]]" }
		for _, r in ipairs(failReasons) do
			table.insert(lines, ("--   %s"):format(r))
		end
		table.insert(lines, "")
		return table.concat(lines, "\n")
	end

	local function resolveBridge()
		if bridgeRemote and bridgeRemote.Parent then return bridgeRemote end
		local rs = game:GetService("ReplicatedStorage")
		bridgeRemote = rs:FindFirstChild("DexBridge")
			or rs:FindFirstChild("LocalGUIEnabler")
			or rs:FindFirstChild("ScriptBridge")
		if not bridgeRemote then
			local auto = Instance.new("RemoteEvent")
			auto.Name = "DexBridge"
			auto.Parent = rs
			bridgeRemote = auto
		end
		return bridgeRemote
	end

	local function pushToBridge(source)
		local remote = resolveBridge()
		if not remote or not remote:IsA("RemoteEvent") then
			return false
		end
		local targetPath = ""
		if currentScript then
			pcall(function()
				targetPath = currentScript:GetFullName()
			end)
		end
		remote:FireServer({
			Type = "ScriptViewerSync",
			Source = source,
			TargetPath = targetPath,
			TargetName = currentScript and currentScript.Name or "",
			PlaceId = game.PlaceId,
			Time = os.time(),
		})
		return true
	end

	-- ============================================================
	-- ScriptViewer API
	-- ============================================================

	ScriptViewer.ViewScript = function(scr)
		if not scr then return end
		currentScript = scr

		-- Validate it's actually a scriptable source container
		local ok, isScript = pcall(function()
			return scr:IsA("LuaSourceContainer")
		end)
		if not ok or not isScript then
			codeFrame:SetText(
				"-- Not a LuaSourceContainer\n-- ClassName: " ..
				(pcall(function() return scr.ClassName end) and scr.ClassName or "unknown")
			)
			window:Show()
			return
		end

		-- Show immediately with a loading indicator so the UI feels responsive
		codeFrame:SetText(("-- Decompiling: %s ..."):format(tostring(scr.Name)))
		window:Show()

		-- SAFETY: Decompile in a coroutine so it doesn't block the Roblox scheduler.
		-- Some executor decompilers can take multiple seconds on large scripts.
		coroutine.wrap(function()
			local source = decompileScript(scr)
			codeFrame:SetText(source)
		end)()
	end

	-- ============================================================
	-- Init
	-- ============================================================

	ScriptViewer.Init = function()
		window = Lib.Window.new()
		window:SetTitle("Script Viewer")
		window:Resize(500, 400)
		ScriptViewer.Window = window

		if Lib.CodeFrame and Lib.CodeFrame.new then
			codeFrame = Lib.CodeFrame.new()
			codeFrame.Frame.Position = UDim2.new(0, 0, 0, 20)
			codeFrame.Frame.Size = UDim2.new(1, 0, 1, -20)
			codeFrame.Frame.Parent = window.GuiElems.Content
		else
			local fallback = Instance.new("TextBox")
			fallback.Name = "CodeFrameFallback"
			fallback.MultiLine = true
			fallback.ClearTextOnFocus = false
			fallback.TextXAlignment = Enum.TextXAlignment.Left
			fallback.TextYAlignment = Enum.TextYAlignment.Top
			fallback.Font = Enum.Font.Code
			fallback.TextSize = 14
			fallback.TextWrapped = false
			fallback.Text = ""
			fallback.TextColor3 = Color3.new(1,1,1)
			fallback.BackgroundColor3 = Color3.fromRGB(36,36,36)
			fallback.BorderSizePixel = 0
			fallback.Position = UDim2.new(0, 0, 0, 20)
			fallback.Size = UDim2.new(1, 0, 1, -20)
			fallback.Parent = window.GuiElems.Content
			codeFrame = {
				Frame = fallback,
				SetText = function(_,txt) fallback.Text = txt or "" end,
				GetText = function() return fallback.Text end,
			}
		end

		-- Copy to Clipboard button
		local copy = Instance.new("TextButton", window.GuiElems.Content)
		copy.BackgroundTransparency = 1
		copy.Size = UDim2.new(0.5, 0, 0, 20)
		copy.Text = "Copy to Clipboard"
		copy.TextColor3 = Color3.new(1, 1, 1)
		copy.MouseButton1Click:Connect(function()
			if env.setclipboard then
				env.setclipboard(codeFrame:GetText())
			end
		end)

		-- Save to File button
		local save = Instance.new("TextButton", window.GuiElems.Content)
		save.BackgroundTransparency = 1
		save.Position = UDim2.new(0.5, 0, 0, 0)
		save.Size = UDim2.new(0.5, 0, 0, 20)
		save.Text = "Save to File"
		save.TextColor3 = Color3.new(1, 1, 1)
			save.MouseButton1Click:Connect(function()
			if not env.writefile then return end
			local source = codeFrame:GetText()
			local filename = ("Place_%s_Script_%s.lua"):format(tostring(game.PlaceId), tostring(os.time()))
			env.writefile(filename, source)
			if movefileas then
				movefileas(filename, ".lua")
			end
			end)

		-- Edit toggle
		local editable = Instance.new("TextButton", window.GuiElems.Content)
		editable.BackgroundTransparency = 1
		editable.Position = UDim2.new(0, 0, 0, 20)
		editable.Size = UDim2.new(0.5, 0, 0, 20)
		editable.Text = "Editor: OFF"
		editable.TextColor3 = Color3.new(1, 1, 1)
		editable.MouseButton1Click:Connect(function()
			local box = codeFrame.Frame
			if box and box:IsA("TextBox") then
				box.TextEditable = not box.TextEditable
				editable.Text = box.TextEditable and "Editor: ON" or "Editor: OFF"
				liveEditEnabled = box.TextEditable
			end
		end)

		-- Server bridge push
		local push = Instance.new("TextButton", window.GuiElems.Content)
		push.BackgroundTransparency = 1
		push.Position = UDim2.new(0.5, 0, 0, 20)
		push.Size = UDim2.new(0.5, 0, 0, 20)
		push.Text = "Send to Server"
		push.TextColor3 = Color3.new(1, 1, 1)
		push.MouseButton1Click:Connect(function()
			if not pushToBridge(codeFrame:GetText()) then
				push.Text = "Bridge Missing"
				return
			end
			push.Text = "Sent"
			task.delay(1.2, function()
				if push.Parent then push.Text = "Send to Server" end
			end)
		end)

		local box = codeFrame.Frame
		if box and box:IsA("TextBox") then
			local liveNonce = 0
			box:GetPropertyChangedSignal("Text"):Connect(function()
				if not liveEditEnabled then return end
				liveNonce = liveNonce + 1
				local myNonce = liveNonce
				task.delay(0.35, function()
					if myNonce ~= liveNonce or not liveEditEnabled then return end
					pushToBridge(box.Text)
				end)
			end)
		end
		end

	return ScriptViewer
end

if gethsfuncs then
	_G.moduleData = {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
else
	return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end
