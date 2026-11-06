--[[
    PBZAchDiag — Phantom Blade Zero achievement-state reader (read-only)

    Reads the achievement record stored inside the save game
    (UPBZAchievementSave.UnlockedIds / PlatformPending) while the game is running,
    because the .sav file itself is encrypted.

    It does NOT write the save, does NOT unlock/reset anything and does NOT call
    any gameplay function. The only engine calls are FindAllOf + property reads.

    Usage: load a save, wait a few seconds, press F7. Output goes to
    pbz_achdiag.txt (next to the game executable) and to UE4SS.log.

    License: MIT
]]

local VERSION   = "1.0.0"
local OUT_FILE  = "pbz_achdiag.txt"   -- relative to the game process CWD; absolute path also works
local CAPTURE   = Key.F7
local HINT      = Key.F6

local f = io.open(OUT_FILE, "a")
local function w(s)
    print("[PBZAchDiag] " .. s)                 -- also lands in UE4SS.log
    if f then f:write(s .. "\n"); f:flush() end
end

-- best effort: FName / FString / UObject / struct -> text
local function s(v)
    if v == nil then return "nil" end
    if type(v) ~= "userdata" then return tostring(v) end
    local ok, r = pcall(function() return v:GetFullName() end)
    if ok and r ~= nil and type(r) ~= "userdata" then return tostring(r) end
    ok, r = pcall(function() return v:get() end)
    if ok and r ~= nil and type(r) ~= "userdata" then return tostring(r) end
    ok, r = pcall(function() return v:ToString() end)
    if ok and r ~= nil and type(r) ~= "userdata" then return tostring(r) end
    return "<ud>"
end

local function num(arr)
    local n = -1
    pcall(function() n = arr:GetArrayNum() end)
    if n < 0 then pcall(function() n = #arr end) end
    return n
end

local function dumpArr(arr, maxn, pad)
    local n = num(arr)
    if n < 0 then return "  (not an array, type=" .. type(arr) .. ")" end
    local out = { "  count=" .. n }
    for i = 1, math.min(n, maxn) do
        local ok, e = pcall(function() return arr[i] end)
        if ok then out[#out + 1] = "  " .. pad .. "[" .. i .. "] " .. s(e)
        else out[#out + 1] = "  " .. pad .. "[" .. i .. "] <read error>" end
    end
    return table.concat(out, "\n")
end

-- turn an array of IDs into a set like { ACH_013 = true }
local function collectIds(arr)
    local set = {}
    local n = num(arr)
    for i = 1, n do
        local ok, e = pcall(function() return arr[i] end)
        if ok then
            local id = s(e):match("ACH_%d+")
            if id then set[id] = true end
        end
    end
    return set
end

w(("=" ):rep(20) .. " PBZAchDiag v" .. VERSION .. " @ " .. os.date("%Y-%m-%d %H:%M:%S") .. " " .. ("="):rep(20))

local tick = 0
LoopInGameThreadWithDelay(2000, function()
    tick = tick + 1
    if tick == 15 then w("[ready] engine ready, press F7 to capture") end
end)

local function grab()
    w("\n---------- capture @ " .. os.date("%Y-%m-%d %H:%M:%S") .. " tick=" .. tick .. " ----------")

    local objs = nil
    local ok = pcall(function() objs = FindAllOf("PBZAchievementSave") end)
    w("[1] FindAllOf ok=" .. tostring(ok) .. " result=" .. tostring(objs ~= nil))
    if objs == nil then w("[end] no object"); return end

    local n = num(objs)
    w("[2] instances=" .. n)
    if n < 1 then w("[end] zero instances"); return end

    local o = objs[1]
    w("[3] obj=" .. s(o))
    local okc, cls = pcall(function() return o:GetClass():GetFullName() end)
    w("[4] class ok=" .. tostring(okc) .. " " .. tostring(cls))

    local okU, u = pcall(function() return o.UnlockedIds end)
    w("[5] UnlockedIds ok=" .. tostring(okU) .. " type=" .. type(u))
    if okU and u ~= nil then w(dumpArr(u, 90, " ")) end

    local okP, p = pcall(function() return o.PlatformPending end)
    w("[6] PlatformPending ok=" .. tostring(okP) .. " type=" .. type(p))
    if okP and p ~= nil then
        local pn = num(p)
        w("  pending count=" .. pn)
        local lim = (pn > 0) and math.min(pn, 5) or 0
        for i = 1, lim do
            pcall(function()
                local e = p[i]
                w("  {account=" .. s(e.AccountKey) .. "}")
                w(dumpArr(e.AchievementIds, 12, "   "))
            end)
        end
    end

    -- summary: which of the 65 regular IDs are absent from this save, plus the meta flag
    if okU and u ~= nil then
        local have = collectIds(u)
        local missing = {}
        for i = 1, 65 do
            local id = string.format("ACH_%03d", i)
            if not have[id] then missing[#missing + 1] = id end
        end
        w("[7] recorded=" .. tostring(num(u)) .. " missing(" .. #missing .. ")=" .. table.concat(missing, ","))
        w("[8] meta ACH_066 recorded=" .. tostring(have["ACH_066"] ~= nil))
    end

    w("[done]")
end

RegisterKeyBind(CAPTURE, function() pcall(grab) end)
RegisterKeyBind(HINT, function() w("[hint] press F7 to capture") end)

w("[load] v" .. VERSION .. " loaded, F7 = capture, F6 = hint; output: " .. OUT_FILE)
