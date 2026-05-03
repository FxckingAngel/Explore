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
				name = "decompile()",
				fn = function(s)
					assert(type(decompile) == "function", "not available")
					return decompile(s)
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

	-- ============================================================
	-- ScriptViewer API
	-- ============================================================

	ScriptViewer.ViewScript = function(scr)
		if not scr then return end

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

		codeFrame = Lib.CodeFrame.new()
		codeFrame.Frame.Position = UDim2.new(0, 0, 0, 20)
		codeFrame.Frame.Size = UDim2.new(1, 0, 1, -20)
		codeFrame.Frame.Parent = window.GuiElems.Content

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
	end

	return ScriptViewer
end

if gethsfuncs then
	_G.moduleData = {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
else
	return {InitDeps = initDeps, InitAfterMain = initAfterMain, Main = main}
end
