# 可视化开发文档 · Visualizing PBZAchDiag

> 目标读者：想在这个只读模组之上做可视化的人（包括未来的你）。
> 本文给出三条技术路线、数据契约、可复用的代码骨架、里程碑与踩坑清单。

---

## 1. 目标与非目标

### 目标

把 `pbz_achdiag.txt` 里那堆 `[1] … [7] …` 的文本，变成**一眼能看懂**的东西：

- 66 个成就的完成矩阵（哪一格空了）；
- 缺口成就的编号与名称（`ACH_053「兵不血刃」`）；
- 待推送队列是否有积压；
- 与 Steam 侧的 65/66 对照，指出"不一致"发生在哪一格。

### 非目标

- **不做**任何写入：不改存档、不解锁成就、不调用 `UnlockAchievement` / `SetAchievement`。这既是安全边界，也是这个项目能公开的前提。
- 不做账号数据上传、不做遥测。

---

## 2. 数据从哪来

### 2.1 采集端（已实现）

`Scripts/main.lua` 在游戏内按 F7 时读取 `PBZAchievementSave`，输出文本。关键行：

```
[5] UnlockedIds ok=true type=userdata
  count=64
   [1] ACH_001
   [2] ACH_051
   ...
[6] PlatformPending ok=true type=userdata
  pending count=0
[7] recorded=64 missing(1)=ACH_053
[8] meta ACH_066 recorded=false
```

### 2.2 输出格式（事实上的数据契约）

| 行 | 正则 | 含义 |
|---|---|---|
| `[5] …` | `^\[5\] UnlockedIds ok=(\w+) type=(\w+)` | 读取是否成功 |
| `  count=N` | `^\s{2}count=(\d+)$` | 记录条数 |
| `   [i] ACH_0xx` | `^\s{3}\[(\d+)\]\s+(ACH_\d{3})$` | 第 i 条成就 ID |
| `[6] … pending count=N` | `pending count=(\d+)` | 待推送队列长度 |
| `[7] recorded=N missing(k)=…` | `missing\((\d+)\)=([^\n]*)` | 汇总：条数与缺口（只统计 `ACH_001`–`ACH_065`） |
| `[8] meta ACH_066 recorded=` | `\[8\] meta ACH_066 recorded=(true\|false)` | 元成就是否已写进这份存档 |

> `[7]` 是 1.0.0 新增的汇总行。解析器应当**优先用 `[5]` 的明细**，`[7]` 作为校验（两者不一致说明版本或编号规则变了）。

### 2.3 一次采集 = 一个快照

每次按 F7 追加一段 `---------- capture @ … ----------`。文件是**追加**模式，解析时要按分隔线切段，取最后一段（或全部段做时间序列）。

```python
import re, pathlib

SEP = re.compile(r"-{10} capture @ ([0-9: \-]+) tick=(\d+) -{10}")
ID  = re.compile(r"^\s{3}\[(\d+)\]\s+(ACH_\d{3})\s*$", re.M)
CNT = re.compile(r"^\s{2}count=(\d+)\s*$", re.M)
PEND= re.compile(r"pending count=(-?\d+)")
SUM = re.compile(r"missing\((\d+)\)=([^\n]*)")
META= re.compile(r"\[8\] meta ACH_066 recorded=(true|false)")

def parse_snapshots(text: str):
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    parts = SEP.split(text)
    out = []
    # parts[0] 是文件头；之后每 3 段为一组 (time, tick, body)
    for i in range(1, len(parts) - 2, 3):
        t, tick, body = parts[i], parts[i + 1], parts[i + 2]
        ids = [m.group(2) for m in ID.finditer(body)]
        out.append({
            "time": t.strip(), "tick": int(tick),
            "count": int(CNT.search(body).group(1)) if CNT.search(body) else len(ids),
            "ids": ids,
            "pending": int(PEND.search(body).group(1)) if PEND.search(body) else -1,
            "missing": (SUM.search(body).group(2).split(",") if SUM.search(body) else []),
            "meta": (META.search(body).group(1) == "true") if META.search(body) else None,
        })
    return out
```

### 2.4 数据模型

```json
{
  "schema": "pbz-achdiag/1",
  "captured_at": "2026-11-06T13:11:58+08:00",
  "account": "self",
  "recorded": 64,
  "pending": 0,
  "meta_recorded": false,
  "achievements": [
    { "id": "ACH_001", "index": 1, "state": "recorded" },
    { "id": "ACH_053", "index": 53, "state": "missing" },
    { "id": "ACH_066", "index": 66, "state": "unknown" }
  ]
}
```

`state` 三态：`recorded`（存档内已记录）/ `missing`（缺口，红框）/ `absent`（元成就 `ACH_066`，未完成属正常，虚线）。

**名称从哪来？** 模组只输出 ID。要显示中文名，需要一张 `ACH_0xx → 名称` 映射表：

- 方案一：`docs/achievements.zh-CN.json`，随仓库分发（注意版权，仅列名称与简短条件）；
- 方案二：读取 Steam 本地缓存 `librarycache/4115450.json`（需用户授权路径，且字段结构随客户端变化）；
- 方案三：只显示 ID + 序号，把名称留给用户自己对照。

推荐方案一，最简单也最稳定。

---

## 3. 三条路线怎么选

| 路线 | 形态 | 难度 | 崩溃风险 | 适用 |
|---|---|---|---|---|
| **A. 外部解析** | 把 txt 拖进网页/桌面工具，出图表 | ★☆☆ | 无 | 首发、分享、写报告 |
| **B. 游戏内覆盖层** | 按 F7 后在游戏里弹一个成就面板 | ★★★ | 中（UMG + UE4SS） | 进阶、直播/实机演示 |
| **C. 实时联动** | 游戏运行中看板自动刷新 | ★★☆ | 低 | 二次开发、长时间观测 |

建议顺序：**A →（可选）C →（谨慎）B**。先把数据变成图，再考虑进游戏里画。

---

## 4. 路线 A：外部可视化（推荐先做）

### 4.1 架构

```
游戏 (UE4SS Lua)
   └─ F7 → pbz_achdiag.txt ──┐
                             ├─ 解析器 (Python/JS) ─→ 统一 JSON
Steam 缓存 (可选) ───────────┘        │
                                      ├─ 终端摘要 (rich/CLI)
                                      ├─ 单文件 HTML 报表（可截图/打印）
                                      └─ PNG 看板 (Pillow)
```

### 4.2 最小实现（Python，约 60 行）

```python
# tools/make_report.py
import json, re, sys, datetime
from pathlib import Path

TOTAL = 66

def load(path):
    text = Path(path).read_text(encoding="utf-8", errors="replace")
    snaps = parse_snapshots(text)
    if not snaps:
        raise SystemExit("没有找到 capture 段，确认按过 F7")
    s = snaps[-1]
    have = set(s["ids"])
    cells = []
    for i in range(1, TOTAL + 1):
        aid = f"ACH_{i:03d}"
        if aid in have:
            state = "recorded"
        elif i == TOTAL:
            state = "absent"          # 元成就，未完成时本来就不在记录里
        else:
            state = "missing"
        cells.append({"id": aid, "index": i, "state": state})
    s["achievements"] = cells
    s["schema"] = "pbz-achdiag/1"
    return s

def summarize(s):
    miss = [c["id"] for c in s["achievements"] if c["state"] == "missing"]
    print(f"记录 {s['count']}/{TOTAL}   待推送 {s['pending']}")
    print("缺口：" + (", ".join(miss) if miss else "无"))

if __name__ == "__main__":
    s = load(sys.argv[1] if len(sys.argv) > 1 else "pbz_achdiag.txt")
    summarize(s)
    Path("report.json").write_text(json.dumps(s, ensure_ascii=False, indent=2), encoding="utf-8")
```

### 4.3 单文件 HTML（无依赖，可直接分享）

把 66 个格子画成 11×6 的网格，用 CSS Grid：

```html
<div class="grid" id="g"></div>
<style>
  .grid{display:grid;grid-template-columns:repeat(11,28px);gap:6px}
  .c{width:28px;height:28px;border-radius:6px;background:#c6a04a}
  .c.miss{background:#fff;border:2px solid #c0392b}
  .c.absent{background:#fff;border:2px dashed #cbd2d9}
</style>
<script>
  const data = window.PBZ_DATA;           // 由 Python 注入
  const g = document.getElementById('g');
  data.achievements.forEach(a => {
    const d = document.createElement('div');
    d.className = 'c ' + (a.state === 'recorded' ? '' : a.state);
    d.title = a.id;
    g.appendChild(d);
  });
</script>
```

要点：

- 颜色只用两种含义：**已记录**（实心金）/ **缺口**（红框）；
- 每格 `title` 放 ID，鼠标悬停即看；
- 顶部放一行结论：`记录 64/66 · 缺口 ACH_053`；
- 打印样式 `@media print` 去掉交互，方便贴进报告。

### 4.4 交付物建议

- `tools/make_report.py`：txt → JSON / HTML / PNG；
- 一个示例 `samples/pbz_achdiag.sample.txt`（**去掉账号信息的假数据**）；
- 一张 `docs/preview.png`（脱敏后）。

---

## 5. 路线 B：游戏内覆盖层（UE4SS + UMG）

### 5.1 先看清约束

1. **不能在模组加载阶段查对象**：UE4SS 的对象表还没就绪，`FindFirstOf` 会让游戏直接 Fatal Error（本项目 v3 就是这样崩的）。
2. **UMG 控件必须挂在一棵已存在的 WidgetTree 上**。本项目验证过的做法（来自同游戏的 `PBZMapMarkers`）是复用**游戏已有界面**的 `WidgetTree` / `RootWidget`，而不是凭空 `CreateWidget`。
3. **数组下标从 1 开始**（`GetArrayNum()` 返回条数，`arr[1]` 是第一个）。
4. **保持引用**：Lua 侧不持有就会 GC，控件树消失或崩溃。用一张模块级表（如 `W.panel`）挂住。

### 5.2 已验证的 UMG 用法（可直接抄）

```lua
local count = 0
local function new(cls, tree)
    count = count + 1
    return StaticConstructObject(StaticFindObject("/Script/UMG." .. cls), tree,
                                 FName("PBZAchDiag" .. cls .. count))
end

local function setText(t, s)
    pcall(function() t:SetText(FText(s)) end)
end

-- 新建一个面板，挂在目标界面的 RootWidget 上
local root = someWidget.WidgetTree.RootWidget
local bg = new("Border", someWidget.WidgetTree)
bg:SetBrushColor({ R = 0.012, G = 0.010, B = 0.008, A = 0.92 })
bg:SetPadding({ Left = 24, Top = 18, Right = 24, Bottom = 18 })

local box = new("VerticalBox", someWidget.WidgetTree)
bg:SetContent(box)

local title = new("TextBlock", someWidget.WidgetTree)
setText(title, "成就记录 64 / 66")
title:SetColorAndOpacity({ SpecifiedColor = { R = 0.92, G = 0.88, B = 0.78, A = 1 }, ColorUseRule = 0 })
box:AddChildToVerticalBox(title):SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 8 })

local slot = root:AddChildToCanvas(bg)
slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
slot:SetAlignment({ X = 0.5, Y = 0.5 })
slot:SetPosition({ X = 0, Y = 0 })
slot:SetZOrder(300)
```

关闭/隐藏：`panel:SetVisibility(1)`（UMG `ESlateVisibility`：0=Visible、1=Collapsed、4=Hidden）。

### 5.3 66 格怎么画

UMG 没有现成的"网格"控件好用，二选一：

- **VerticalBox × 6 行，每行 HorizontalBox × 11 格**：每格一个 `Border` + 一个 `TextBlock`（或纯 `Border`，靠 `title` 提示）。稳定、易定位。
- **UniformGridPanel**：`AddChildToUniformGrid`，但要算 `Row/Column`，API 兼容性不如前者稳。

推荐第一种。伪代码：

```lua
local rows = {}
for r = 1, 6 do
    local row = new("HorizontalBox", tree)
    box:AddChildToVerticalBox(row):SetPadding({ Left = 0, Top = 0, Right = 0, Bottom = 4 })
    rows[r] = row
    for c = 1, 11 do
        local idx = (r - 1) * 11 + c
        local cell = new("Border", tree)
        cell:SetPadding({ Left = 2, Top = 2, Right = 2, Bottom = 2 })
        row:AddChildToHorizontalBox(cell):SetPadding({ Left = 0, Top = 0, Right = 4, Bottom = 0 })
        -- idx <= 66 才有效
    end
end
```

刷新时**不要重建整棵树**：把 `cell` 存进 `cells[idx]`，只改颜色/可见性。

### 5.4 数据与 UI 的绑定

采集逻辑与现有 `grab()` 完全一致，只把 `w()` 换成"更新 UI"：

```
按 F7
 ├─ FindAllOf("PBZAchievementSave")
 ├─ 读 UnlockedIds → set
 ├─ 计算 66 个 state
 ├─ 更新 cells[i] 的颜色
 └─ 更新标题 "记录 64/66 · 缺口 ACH_053"
```

### 5.5 挂在哪

| 挂载点 | 优点 | 缺点 |
|---|---|---|
| 游戏已有界面（背包/地图/设置）的 `WidgetTree` | 已验证可行 | 只在那个界面可见 |
| 自己 `CreateWidget` + `AddToViewport` | 全局可见 | 本作未验证，可能拿不到有效 `WidgetTree`，失败会崩 |
| HUD 控件 | 常驻 | 需要找到 HUD 的 WidgetTree，版本相关 |

建议：**先做"打开背包/地图时显示"**，跑通后再考虑常驻。

### 5.6 崩溃风险清单

| 风险 | 规避 |
|---|---|
| 加载阶段查对象 | 只在按键回调 / `LoopInGameThreadWithDelay` 里查 |
| 访问无效控件（界面已关闭） | 每次用 `o:IsValid()` 或 `pcall` 包住 |
| 每帧重建控件 | 只在数据变化时重建，平时只改颜色 |
| 控件被 GC | 模块级变量持有引用 |
| 跨线程调用 | 所有 UMG 操作都在游戏线程回调里做 |

---

## 6. 路线 C：实时联动（可选）

`main.lua` 增加一个开关（默认关闭）：

```lua
-- 每 10 秒把最新快照写成 JSON（只读，仍然是同一份数据）
LoopInGameThreadWithDelay(10000, function()
    if not ENABLE_LIVE then return end
    if not lastSnapshot then return end
    local f = io.open("pbz_achdiag.json", "w")
    if f then f:write(lastSnapshot); f:close() end
end)
```

外部工具用 `watchdog` / `chokidar` 监听文件变化即可刷新看板。

> 注意：UE4SS 的 Lua 没有网络栈，**不要**指望在模组里起 HTTP 服务；要联网请走外部进程。

---

## 7. 目录与代码骨架

```
PBZAchDiag/
├── Scripts/main.lua              # 采集端（已有）
├── docs/
│   ├── VISUALIZATION.md          # 本文
│   └── achievements.zh-CN.json   # ID → 名称（选配）
├── tools/
│   ├── parse.py                  # txt → 统一 JSON
│   ├── make_report.py            # JSON → HTML / PNG
│   └── viewer.html               # 单文件查看器
└── samples/
    └── pbz_achdiag.sample.txt    # 脱敏样例
```

---

## 8. 里程碑

| 阶段 | 内容 | 工作量 | 验收 |
|---|---|---|---|
| M1 | 解析器 + 终端摘要 | 0.5 天 | 一条命令打印 `记录 64/66 · 缺口 ACH_053` |
| M2 | 单文件 HTML 报表 | 1 天 | 双击打开即见 11×6 网格，缺口红框，可打印 |
| M3 | 游戏内面板（复用 WidgetTree） | 2–3 天 | 按 F7 弹出面板，数字与 txt 一致，退出界面不残留 |
| M4 | 实时看板（可选） | 1–2 天 | 游戏中按 F7，浏览器 1 秒内刷新 |

---

## 9. 测试清单

- [ ] 64/66 的存档：网格 64 实心 + 2 空（`ACH_053` 红框、`ACH_066` 虚线）；
- [ ] 65/66 的存档：只剩 `ACH_066` 空；
- [ ] 66/66 的存档：全实心，标题显示"已完成"；
- [ ] 连续按两次 F7：追加两段，解析器取最后一段；
- [ ] 文件被截断（游戏崩溃）：解析器不抛异常，给出"数据不完整"提示；
- [ ] 老版本输出（没有 `[7]` 行）：回退到用 `[5]` 明细计算缺口；
- [ ] 游戏内面板：开关界面 5 次不崩、不重复叠加。

---

## 10. 合规与发布注意

- 仓库里**不要**提交真实 `pbz_achdiag.txt`（含 SteamID64、账号目录名）；
- 截图/看板发布前把账号栏打码；
- 保持只读定位：任何"顺手修一下成就"的功能都不要进这个仓库；
- 第三方工具链（UE4SS）有崩溃风险，README 里已经声明，可视化工具同样要写清楚"数据仅供参考"。

---

## 附：一个最小的端到端示例

```powershell
# 1. 游戏里按 F7，生成 pbz_achdiag.txt
# 2. 解析
python tools/parse.py "D:\...\pbz_achdiag.txt" > report.json
# 3. 出图
python tools/make_report.py report.json --html report.html --png report.png
# 4. 打开
start report.html
```
