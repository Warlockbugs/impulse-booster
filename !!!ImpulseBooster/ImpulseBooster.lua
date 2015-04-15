-- Name: ImpulseBooster
-- License: LGPL v2.1
local _G, _ = _G or getfenv()
local ipairs, pairs, type, tostring, tonumber = ipairs, pairs, type, tostring, tonumber
local abs = math.abs
local find, format, gsub, lower = string.find, string.format, string.gsub, string.lower
local concat = table.concat
-- Custom Lua
local function isfunc(f) return type(f) == "function"; end
local function isnum(n) return type(n) == "number"; end
local function isstr(s) return type(s) == "string"; end
local function istable(t) return type(t) == "table"; end
local function isframe(f) return istable(f) and isfunc(f.GetFrameType); end
local function importentity(i) if not istable(i) then return; end; for e, l in pairs(i) do local o = (istable(e) and e) or (e == "WoW" and _G) or _G[e]; if not istable(o) then return nil, e; end; for t, a in pairs(l) do for _, c in ipairs(a) do if type(o[c]) ~= t then return nil, e, c, t; end; end; end; end; return true; end
local function print(s) return DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME:AddMessage("[ImpulseBooster]: "..tostring(s), 1, .5, .5); end
local function error(o, c, t, s) return print(concat({s or "Error:", (o and ((c and format("Your %q version is not compatible (%q is not a %q).", o, c, t)) or format("Unable to locate %q.", o))) or "Unexpected error."}, " ")); end
local function fatal(o, c, t) return error(o, c, t, "Loading aborted:"); end
-- Check for static compatibility with entity importer:
do
	local import = {
		["WoW"] = { ["function"] = { "CreateFrame", "GetAddOnInfo", "GetAddOnMetadata", "GetCVar", "GetNumAddOns", "GetRefreshRates", "GetScreenResolutions", "GetTime", "RegisterCVar", "RestartGx", "SetCVar" }, },
		["bit"] = { ["function"] = { "lshift", "bor", "band", "bnot" }, },
	}
	local r, o, c, t = importentity(import)
	if not r then return fatal(o, c, t); end
end
-- Custom globals and API
local WOW = tonumber((gsub(((GetBuildInfo and GetBuildInfo()) or "1.8.4"), "^([%d]+)%.([%d]+)%.([%d]+)$", function(mj,mn,hf) return (mj*10^4)+(mn*100)+hf; end)))
local MAX_WOW_FRAMERATE = (WOW < 30000 and 1000) or 10000
local lshift, bor, band, bnot = bit.lshift, bit.bor, bit.band, bit.bnot
local GetTime = GetTime
local GetAddOnMetadata = GetAddOnMetadata
local GetAddOnInfo = GetAddOnInfo
local GetCVar = GetCVar
local GetRefreshRates = GetRefreshRates
local RegisterCVar = RegisterCVar
local RestartGx = RestartGx
local SetCVar = SetCVar
local function GetAvailableRefreshRates(mode, modes) local r = {}; for i,m in ipairs(modes) do if m == mode then for i,rate in ipairs({GetRefreshRates(i)}) do r[rate] = i; end; end; end; return r; end
local function GetCVarNum(cvar)	return tonumber(GetCVar(cvar)); end -- Function: Get CVar's numeric value (or nil)
local function GetMaxFPS() return GetCVarNum("maxFPS") or 0; end
local function GetMaxFPSBG() return GetCVarNum("maxFPSBk") or 0; end
local function GetResolution() return GetCVar("gxResolution"); end
local function GetRefreshRate() return GetCVarNum("gxRefresh") or 0; end
local function GetVSync() return (GetCVarNum("gxVSync") or 0) > 0; end
local function UseCVars(cvars) if istable(cvars) then for k,v in pairs(cvars) do if isstr(v) then RegisterCVar(v, nil); end; end; end; end -- Registering non-existent CVars on old clients will suppress errors
--
UseCVars({"coresDetected", "gxRefresh", "gxResolution", "gxVSync", "maxFPS", "maxFPSBk", "scriptMemory", "timingMethod", "timingTestError", "processAffinityMask"})
local ADDONS_NUM = GetNumAddOns()
local ADDONS_NUM_ENABLED = 0
local ADDONS_NUM_BLOATED_RATIO = 0
local ADDONS_MEM_LIMITER = (GetCVarNum("scriptMemory") ~= nil)
local ADDONS_MAX_MEM = GetCVarNum("scriptMemory") or 0
--
local DISPLAY_RESOLUTIONS = {GetScreenResolutions()}
local DISPLAY_LAST_CHECK = 0
local DISPLAY_RESOLUTION = GetResolution()
local DISPLAY_RATES = GetAvailableRefreshRates(DISPLAY_RESOLUTION, DISPLAY_RESOLUTIONS)
local DISPLAY_RATE = GetRefreshRate()
local DISPLAY_VSYNC = GetVSync()
local DISPLAY_FPS_LIMITER = (WOW >= 20200 and GetCVarNum("maxFPS") ~= nil and GetCVarNum("maxFPSBk") ~= nil)
local DISPLAY_MAX_FPS = (GetMaxFPS() < 0 and DISPLAY_RATE) or GetMaxFPS()
local DISPLAY_MAX_FPS_BG = GetMaxFPSBG()
local DISPLAY_IBSYNC = DISPLAY_FPS_LIMITER and not DISPLAY_VSYNC and DISPLAY_RATES[DISPLAY_MAX_FPS] ~= nil
local DISPLAY_IBSYNC_BURNOUT = (GetMaxFPS() < 0)
--
local CPU_NUM_THREADS = GetCVarNum("coresDetected") or 0
local CPU_AFFINITY = GetCVarNum("processAffinityMask") or 0
local CPU_TIMING = GetCVarNum("timingMethod") or 0
local CPU_IS_ASYNC = ((GetCVarNum("timingTestError") or 0) ~= 0)
local CPU_NEW_AFFINITY = false
local CPU_NEW_TIMING = false
--
local TIME_LOADING_START = 0
local TIME_LOADING_END = 0
--
if ADDONS_NUM > 0 then -- Enabled and bloated addons detaction: 
	local bloat, loading = 0, 0
	local keytags = { "Title", "Dependencies", "RequiredDeps", "OptionalDeps" }
	local name, enabled, loadable, reason, metadata
	for i=1, ADDONS_NUM do
		name, _, _, enabled, loadable, reason = GetAddOnInfo(i)
		if enabled then
			loading = loading + 1
			if GetAddOnMetadata(i, "X-Embeds") ~= nil then bloat = bloat + 1; end
			for _, tag in ipairs(keytags) do
				metadata = GetAddOnMetadata(i, tag)
				if metadata ~= nil and (find(metadata, "[Ll]ib") or find(metadata, "[Aa]ce")) then
					bloat = bloat + 1
					break
				end
			end
		end
	end
	ADDONS_NUM_ENABLED = loading
	ADDONS_NUM_BLOATED_RATIO = (bloat / loading)
end
--
local function CreateProcessAffinityMask(numCores, advised)
	local mask = 0
	for i=1, ((numCores > 32 and 32) or (numCores < 1 and 0) or numCores) do mask = bor(lshift(mask, 1), 1); end
	return (advised and band(mask, bnot(1))) or mask
end
--
local function SetMaxFPS(fps) return SetCVar("maxFPS", (fps or ((GetMaxFPS() < MAX_WOW_FRAMERATE and MAX_WOW_FRAMERATE) or DISPLAY_MAX_FPS))); end
--
local function ToggleMulticoreCpuTweaks()
	-- CPU timing correcting tweak:
	local timingNew = ((not CPU_IS_ASYNC and CPU_TIMING == 1) and 0) or ((CPU_IS_ASYNC and CPU_TIMING ~= 1) and 1) or nil 
	if timingNew ~= nil then
		CPU_NEW_TIMING = true
		SetCVar("timingMethod", timingNew)
	end
	-- Auto-affinity tweak: Only for clients < 3.3.2 and multicore CPUs (except dualcores).
	-- Current code targets (numCores - 1) for a number of reasons, but this may change in the future.
	if CPU_NUM_THREADS > 2 and WOW < 30302 then
		local advisedAffinity = CreateProcessAffinityMask(CPU_NUM_THREADS, true)
		-- Check if user has a custom setting with less cores (possibly assigned by the client)
		-- Do tweak if:
		-- a) Client already doesn't have a user picked value of all cores
		-- b) Client has default affinity range
		if advisedAffinity ~= 0 and (CPU_AFFINITY <= 3 or CPU_AFFINITY < advisedAffinity) then
			CPU_NEW_AFFINITY = true
			SetCVar("processAffinityMask", advisedAffinity)
		end
	end
end
--
local function ToggleFrameRateLimit(loading)
	if loading and (ADDONS_NUM_BLOATED_RATIO > .1 or ADDONS_NUM_ENABLED > 15) then
		if DISPLAY_VSYNC and isfunc(RestartGx) then
			SetCVar("gxVSync", (GetVSync() and 0) or 1)
			RestartGx()
			SetMaxFPS()
		elseif not DISPLAY_VSYNC then
			SetMaxFPS()
		end
	end
end
--
local function UpdateDisplayMode(toggle)
	if isnum(toggle) then
		if toggle > 0 then
			return DISPLAY_RATES[DISPLAY_RATE] ~= nil and not DISPLAY_IBSYNC and SetMaxFPS(DISPLAY_RATE)
		end
		return DISPLAY_IBSYNC and SetMaxFPS(0)
	end
	local oldsync = DISPLAY_IBSYNC
	DISPLAY_RESOLUTION = GetResolution()
	DISPLAY_RATES = GetAvailableRefreshRates(DISPLAY_RESOLUTION, DISPLAY_RESOLUTIONS)
	DISPLAY_RATE = GetRefreshRate()
	DISPLAY_VSYNC = GetVSync()
	DISPLAY_MAX_FPS = GetMaxFPS()
	DISPLAY_MAX_FPS_BG = GetMaxFPSBG()
	DISPLAY_IBSYNC = not DISPLAY_VSYNC and DISPLAY_RATES[DISPLAY_MAX_FPS] ~= nil
	if DISPLAY_IBSYNC and DISPLAY_MAX_FPS ~= DISPLAY_RATE then
		SetMaxFPS((DISPLAY_RATES[DISPLAY_RATE] ~= nil and DISPLAY_RATE) or 0)
		if DISPLAY_RATES[DISPLAY_RATE] == nil then print(format("Your display doesn't support %iHz mode, reverting IBSync...", DISPLAY_RATE)); end
	end
	return DISPLAY_IBSYNC ~= oldsync and print(format("ImpulseBooster Sync is now %s.", ((DISPLAY_IBSYNC and "enabled") or "disabled")))
end
--
local BOOSTER = CreateFrame("Frame")
--
local function OnUpdate()
	if (GetTime() - DISPLAY_LAST_CHECK) < 3 then return; end
	DISPLAY_LAST_CHECK = GetTime()
	if GetVSync() ~= DISPLAY_VSYNC then return UpdateDisplayMode(); end
	if GetResolution() ~= DISPLAY_RESOLUTION then return UpdateDisplayMode(); end
	if GetRefreshRate() ~= DISPLAY_RATE then return UpdateDisplayMode(); end
	if GetMaxFPS() ~= DISPLAY_MAX_FPS then return UpdateDisplayMode(); end
	if GetMaxFPSBG() ~= DISPLAY_MAX_FPS_BG then return UpdateDisplayMode(); end
end
--
local function OnEvent()
	if event == "ADDON_LOADED" and arg1 == "!!!ImpulseBooster" then
		TIME_LOADING_START = GetTime()
		BOOSTER:UnregisterEvent("ADDON_LOADED")
		ToggleMulticoreCpuTweaks()
		ToggleFrameRateLimit(true)
	elseif event == "PLAYER_LOGIN" then
		TIME_LOADING_END = GetTime()
		ToggleFrameRateLimit(true)
		if CPU_NEW_TIMING then
			print("Detected incorrect forced timing method, applying the fix on the next restart...")
		end
		if CPU_NEW_AFFINITY then
			print("Assigned a new CPU core affinity. Please, restart the game...")
		end
		local stats = format("UI startup: %.2fs", abs(TIME_LOADING_END - TIME_LOADING_START))
		if ADDONS_MEM_LIMITER and ADDONS_MAX_MEM > 0 then
			stats = format("%s (Heap: %.1f MB)", stats, abs(ADDONS_MAX_MEM / 1024))
		end
		if CPU_NUM_THREADS > 0 then
			stats = format("%s; CPU:%s%i thread(s) (Affinity: %i)", stats, ((CPU_IS_ASYNC and " [ASYNC] ") or " "), CPU_NUM_THREADS, CPU_AFFINITY)
		end
		if DISPLAY_FPS_LIMITER then
			stats = format("%s; IBSync: %s", stats, ((DISPLAY_IBSYNC and "on") or "off"))
		end
		print(stats)
	elseif event == "PLAYER_LOGOUT" and DISPLAY_IBSYNC and DISPLAY_IBSYNC_BURNOUT then
		SetMaxFPS(-1)
	end
end
--
BOOSTER:RegisterEvent("ADDON_LOADED")
BOOSTER:RegisterEvent("PLAYER_LOGIN")
BOOSTER:RegisterEvent("PLAYER_LOGOUT")
BOOSTER:SetScript("OnEvent", OnEvent)
BOOSTER:SetScript("OnUpdate", (DISPLAY_FPS_LIMITER and OnUpdate) or nil)
--
do -- Inject Video Options
	if not DISPLAY_FPS_LIMITER then SetCVar("maxFPS", nil); SetCVar("maxFPSBk", nil); return; end
	local optionsvideo = _G["OptionsFrameDisplay"]
	local attachto = _G["OptionsFrameCheckButton14"] -- Hardware cursor checkbox for TBC clients
	local checkboxvsync = _G["OptionsFrameCheckButton5"]
	local OptionsFrame_UpdateCheckboxes = _G["OptionsFrame_UpdateCheckboxes"]
	local OptionsFrame_Save = _G["OptionsFrame_Save"]
	if not isframe(optionsvideo) or not isframe(attachto) or not isframe(checkboxvsync) or not isfunc(OptionsFrame_UpdateCheckboxes) or not isfunc(OptionsFrame_Save) then return; end
	local checkbox = CreateFrame("CheckButton", "OptionsFrameCheckButtonIB1", optionsvideo, "OptionsCheckButtonTemplate")
	local checkbox2 = CreateFrame("CheckButton", "OptionsFrameCheckButtonIB2", optionsvideo, "OptionsCheckButtonTemplate")
	_G[checkbox:GetName().."Text"]:SetText("|cFFFF8080ImpulseBooster Sync|r")
	checkbox.tooltipText = "VSync alternative:\n|cFFFF8080ImpulseBooster|r will synchronize your FPS to your display's refresh rate with frame rate limiter while playing and boost UI loading speed."
	checkbox.tooltipRequirement = "This option eliminates the need for graphics engine's restart to boost UI loading speed, while keeping benefits of VSync."
	checkbox:SetPoint("TOP", attachto, "BOTTOM", 0, 4)
	checkbox:SetScript("OnShow", function() return this:SetChecked(DISPLAY_IBSYNC); end)
	checkbox:SetScript("OnClick", function()
		checkboxvsync:SetChecked(DISPLAY_VSYNC and not this:GetChecked())
		if not this:GetChecked() then checkbox2:SetChecked(false); end
		return PlaySound((this:GetChecked() and "igMainMenuOptionCheckBoxOn") or "igMainMenuOptionCheckBoxOff")
	end)
	_G[checkbox2:GetName().."Text"]:SetText("|cFFFF8080Disable in menus|r")
	checkbox2:SetWidth(26)
	checkbox2:SetHeight(26)
	checkbox2.tooltipText = "|cFFFF8080ImpulseBooster|r will disable IBSync on logout. This is similar to disabling VSync, but only for menus. This will offer additional UI logout/loading speed boosts, but at cost of additional strain on your GPU."
	checkbox2.tooltipRequirement = "This option is not generally recommended, because excess FPS in menus may cause unwanted side effects on your GPU, such as overheating and coil whine."
	checkbox2:SetPoint("TOP", checkbox, "BOTTOM", 5, 4)
	checkbox2:SetScript("OnShow", function() return this:SetChecked(DISPLAY_IBSYNC_BURNOUT and DISPLAY_IBSYNC); end)
	checkbox2:SetScript("OnClick", function()
		if not checkbox:GetChecked() then this:SetChecked(false); end
		return PlaySound((this:GetChecked() and "igMainMenuOptionCheckBoxOn") or "igMainMenuOptionCheckBoxOff")
	end)
	_G["OptionsFrame_UpdateCheckboxes"] = function()
		OptionsFrame_UpdateCheckboxes()
		if checkboxvsync:GetChecked() then
			checkbox:SetChecked(false)
		end
	end
	_G["OptionsFrame_Save"] = function()
		OptionsFrame_Save()
		UpdateDisplayMode((checkbox:GetChecked() and 1) or 0)
		DISPLAY_IBSYNC_BURNOUT = DISPLAY_IBSYNC and checkbox2:GetChecked()
	end
end
