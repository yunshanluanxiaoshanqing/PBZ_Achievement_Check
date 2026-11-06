--[[
    影之刃零 · 成就检测（只读）
    Phantom Blade Zero - achievement check (read-only)

    版本：1.1.0
    许可：MIT

    作用：
        游戏把「已解锁成就」记录在存档内部（PBZAchievementSave.UnlockedIds），
        而 .sav 文件本身是加密的。本模组在游戏运行时读取这份记录，输出一份文本报告，
        并在桌面生成一张示意图，用来判断「还差哪个成就没被存档记住」。

    安全：
        只做对象查找和属性读取，不修改存档、不调用任何解锁 / 重置接口。

    用法：
        进入游戏并载入存档，等几秒，按 F7。输出见游戏根目录的文本报告。
]]

local VERSION  = "1.1.0"
local OUT_NAME = "PBZ_Achievement_Check.txt"   -- 写在游戏根目录
local CAPTURE  = Key.F7
local HINT     = Key.F6
local AUTO_PNG = true                          -- 检测完成后自动在桌面生成图片
local TOTAL    = 65                            -- 常规成就数量，ACH_066 是「完成其余全部成就」的元成就

-- 游戏进程的工作目录是 ...\ProjectPBZ\Binaries\Win64，向上三级即游戏根目录
local ROOT = "../../../"
-- 图片渲染脚本（与本模组放在同一目录）
local PS1  = ROOT .. "platform/steam/ue4ss/Mods/PBZAchDiag/Report.ps1"

-- ============================================================
-- 成就 ID → 中文名（取自 Steam 成就定义，用于报告里的可读名称）
-- ============================================================
local NAMES = {
    ["ACH_001"] = "寻心路",
    ["ACH_002"] = "逆行不逆心",
    ["ACH_003"] = "黑塔蔽天光",
    ["ACH_004"] = "茫茫无立处",
    ["ACH_005"] = "蒙花不解厄",
    ["ACH_006"] = "纵身赴危局",
    ["ACH_007"] = "世浊人心空",
    ["ACH_008"] = "是非谁人定",
    ["ACH_009"] = "故人今何处",
    ["ACH_010"] = "水天纵浊流",
    ["ACH_011"] = "碧血照重明",
    ["ACH_012"] = "霜雪正堪行",
    ["ACH_013"] = "昭昭心与血",
    ["ACH_014"] = "巨斧余恨",
    ["ACH_015"] = "红妆鬼斩",
    ["ACH_016"] = "猎杀",
    ["ACH_017"] = "千杯散尽",
    ["ACH_018"] = "镜碎蛇影无",
    ["ACH_019"] = "来日可如约？",
    ["ACH_020"] = "焰尽狮魂传",
    ["ACH_021"] = "剑横北斗",
    ["ACH_022"] = "血滴歧路",
    ["ACH_023"] = "物善其用",
    ["ACH_024"] = "皆归尘土",
    ["ACH_025"] = "白影巍巍",
    ["ACH_026"] = "“锯理力争”",
    ["ACH_027"] = "大梦终须醒",
    ["ACH_028"] = "独步烟波",
    ["ACH_029"] = "四释“玉”囚",
    ["ACH_030"] = "刀冠双绝",
    ["ACH_031"] = "力挫三差",
    ["ACH_032"] = "禁法湖底沉",
    ["ACH_033"] = "“影”承血，“刃”同源",
    ["ACH_034"] = "白山遗烈",
    ["ACH_035"] = "白首不相离",
    ["ACH_036"] = "浪子侠心",
    ["ACH_037"] = "鬼斩客",
    ["ACH_038"] = "杏林有继",
    ["ACH_039"] = "妙手拾遗",
    ["ACH_040"] = "草木也知愁",
    ["ACH_041"] = "神“器”十足",
    ["ACH_042"] = "一力降十会",
    ["ACH_043"] = "珀力非凡",
    ["ACH_044"] = "且听花声",
    ["ACH_045"] = "取石有道",
    ["ACH_046"] = "博物杂记",
    ["ACH_047"] = "“影”多不压身",
    ["ACH_048"] = "一巧破百拙",
    ["ACH_049"] = "“影”之道",
    ["ACH_050"] = "“刃”之道",
    ["ACH_051"] = "破伤风之刃",
    ["ACH_052"] = "醉生梦死",
    ["ACH_053"] = "兵不血刃",
    ["ACH_054"] = "灭烛见真火",
    ["ACH_055"] = "渴饮刀头血",
    ["ACH_056"] = "御雪凝霜",
    ["ACH_057"] = "一刀两断",
    ["ACH_058"] = "延时爆破",
    ["ACH_059"] = "环环相扣",
    ["ACH_060"] = "白山风雷动",
    ["ACH_061"] = "天降金瓜",
    ["ACH_062"] = "翻江倒海",
    ["ACH_063"] = "拳力以赴",
    ["ACH_064"] = "电光石火",
    ["ACH_065"] = "无中生友",
    ["ACH_066"] = "逆天改命",
}
local META = "ACH_066"   -- 元成就：完成其余全部成就

-- 输出到 UE4SS.log，方便排查
local function log(s)
    print("[PBZAchDiag] " .. s .. "\n")   -- UE4SS 的 print 不会自动换行
end

-- 把 FName / FString / UObject 之类的值尽量转成字符串
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

-- 读取 UE4SS 数组的长度
local function num(arr)
    local n = -1
    pcall(function() n = arr:GetArrayNum() end)
    if n < 0 then pcall(function() n = #arr end) end
    return n
end

-- 把 ID 数组转成集合 { ACH_013 = true }
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

-- 拼出报告文本
local function buildReport(have, pending, path)
    local time = os.date("%Y-%m-%d %H:%M:%S")
    local recorded = 0
    for i = 1, TOTAL do
        if have[string.format("ACH_%03d", i)] then recorded = recorded + 1 end
    end

    local missing = {}
    for i = 1, TOTAL do
        local id = string.format("ACH_%03d", i)
        if not have[id] then missing[#missing + 1] = id end
    end

    local L = {}
    L[#L + 1] = "影之刃零 · 成就检测报告"
    L[#L + 1] = "生成时间：" .. time
    L[#L + 1] = "检测来源：当前存档内的成就记录（PBZAchievementSave.UnlockedIds）"
    L[#L + 1] = string.format("存档记录：%d / %d", recorded, TOTAL)
    L[#L + 1] = "缺失数量：" .. #missing
    L[#L + 1] = "元成就：" .. META .. "  已记录=" .. tostring(have[META] ~= nil)
    L[#L + 1] = "待推送队列：" .. tostring(pending)
    if #missing == 0 then
        L[#L + 1] = "结论：全部成就均已记录，存档状态完整。"
    else
        L[#L + 1] = "结论：存在缺失，需要在当前存档里重新完成对应条件。"
    end

    L[#L + 1] = ""
    L[#L + 1] = "【缺失成就】"
    if #missing == 0 then
        L[#L + 1] = "（无）"
    else
        for _, id in ipairs(missing) do
            L[#L + 1] = id .. "  " .. (NAMES[id] or "未知成就")
        end
    end

    L[#L + 1] = ""
    L[#L + 1] = "【已记录成就】"
    for i = 1, TOTAL do
        local id = string.format("ACH_%03d", i)
        if have[id] then L[#L + 1] = id .. "  " .. (NAMES[id] or "未知成就") end
    end

    L[#L + 1] = ""
    L[#L + 1] = "由 PBZAchDiag 生成 · 只读检测，未修改存档"
    return table.concat(L, "\n"), recorded, #missing, missing, path
end

-- 写文件：优先游戏根目录，失败则退回当前工作目录
local function writeFile(text)
    local fh = io.open(ROOT .. OUT_NAME, "w")
    local path = ROOT .. OUT_NAME
    if not fh then
        fh = io.open(OUT_NAME, "w")
        path = OUT_NAME
    end
    if not fh then return nil end
    fh:write(text)
    fh:close()
    return path
end

-- 调用 PowerShell 把文本报告渲染成桌面图片（失败不影响主流程）
local function renderPng(txt)
    if not AUTO_PNG then return end
    local cmd = string.format(
        'start "" /b powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%s" -Txt "%s"',
        PS1, txt)
    log("[png] 正在生成桌面图片，游戏会卡顿几秒…")
    local ok, err = pcall(function() os.execute(cmd) end)
    if not ok then
        log("[png] 自动生成失败：" .. tostring(err))
        log("[png] 可手动双击游戏目录下的 生成图片.cmd")
    end
end

-- 主流程：读取记录 → 生成文本 → 生成图片
local function capture()
    log("---------- 开始检测 @ " .. os.date("%Y-%m-%d %H:%M:%S") .. " ----------")

    local objs
    local ok = pcall(function() objs = FindAllOf("PBZAchievementSave") end)
    if not ok or objs == nil then
        log("[x] 未能找到成就记录对象，请确认已载入存档")
        return
    end

    local n = num(objs)
    if n < 1 then
        log("[x] 成就记录对象数量为 0，请先载入存档")
        return
    end

    local o = objs[1]
    local have = {}
    local okU, u = pcall(function() return o.UnlockedIds end)
    if okU and u ~= nil then have = collectIds(u) end

    local pending = "?"
    local okP, p = pcall(function() return o.PlatformPending end)
    if okP and p ~= nil then pending = tostring(num(p)) end

    local text, recorded, missingCount, missing = buildReport(have, pending, "")
    local path = writeFile(text)
    if not path then
        log("[x] 无法写入报告文件")
        return
    end

    log(string.format("[ok] 存档记录 %d / %d，缺失 %d 项", recorded, TOTAL, missingCount))
    for _, id in ipairs(missing) do
        log("     缺少  " .. id .. "  " .. (NAMES[id] or ""))
    end
    log("[ok] 报告已写入：" .. path)

    renderPng(path)
    log("[done]")
end

-- 加载后等待引擎就绪，再允许检测
local tick = 0
LoopInGameThreadWithDelay(2000, function()
    tick = tick + 1
    if tick == 15 then log("[ready] 已就绪，按 F7 开始检测") end
end)

RegisterKeyBind(CAPTURE, function() pcall(capture) end)
RegisterKeyBind(HINT, function() log("[hint] 按 F7 开始检测") end)

log("[load] v" .. VERSION .. " 已加载，F7 = 检测，F6 = 提示")
