# PBZAchDiag · 影之刃零成就记录读取器

一个**只读**的 UE4SS Lua 模组，用于在《影之刃零》（Phantom Blade Zero）运行时读取**存档内的成就记录**（`UnlockedIds`）与**待推送队列**（`PlatformPending`）。

用于诊断这一类问题：**Steam 成就页显示 65/66，只剩最后一个成就不弹，重打 Boss、重启游戏都没用。**

> Read-only UE4SS mod that dumps the achievement record stored inside a Phantom Blade Zero save, to diagnose "Steam shows N-1 achievements but the last one never unlocks".

---

## 为什么需要它

- 存档 `PBZSaveGame.sav` 是加密容器（`PBZS` 魔数、24 个分块、每块 32 字节盐值、整体信息熵 ≈ 7.997 bit/byte），**无法直接读取或编辑**。
- 但游戏在运行时把成就记录放在内存对象 `PBZAchievementSave` 里，字段为 `UnlockedIds`（本存档已记录的成就）和 `PlatformPending`（待推送到平台的条目）。
- 游戏的"完成其余全部成就"类元成就（`EPBZAchievementTrigger::MetaAll`）**以存档内这份记录为判据**，而不是 Steam 账号数据。

两者一旦不一致，就会出现死锁：Steam 侧 65/66，存档内 64/65，元成就永远差一条，且因为再也没有"新的解锁事件"，判定不会被再次触发。

## 它安全吗

- 只调用 `FindAllOf("PBZAchievementSave")` 和属性读取；
- **不写入**存档、**不修改**任何游戏数据；
- **不调用** `UnlockAchievement` / `ResetAchievements` / `SetAchievement` 等任何接口；
- 代码不到 150 行，全部逻辑可在 `Scripts/main.lua` 中逐行核对。

## 环境要求

| 项目 | 版本 |
|---|---|
| 游戏 | Phantom Blade Zero（Steam AppID 4115450），测试于 build 26367565 / 2026-11-04 |
| 加载器 | [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) v3.0.1 Beta（游戏目录 `platform\steam\ue4ss`） |
| 其它 | 无 |

## 安装

1. 确认游戏目录已装好 UE4SS，且 `platform\steam\ue4ss\Mods\` 存在；
2. 把 `PBZAchDiag` 整个文件夹放进 `...\ue4ss\Mods\`；
3. 确认 `PBZAchDiag\enabled.txt` 存在（这是 UE4SS 的自动加载开关）；
4. 启动游戏。

目录结构应如下：

```
platform\steam\ue4ss\Mods\PBZAchDiag\
├── enabled.txt
└── Scripts\
    └── main.lua
```

## 使用

1. 进入游戏，读取任意一个存档（进入实际游玩场景即可）；
2. 等 3～5 秒，让引擎就绪；
3. 按 **F7**；
4. 结果写入两个地方：
   - `pbz_achdiag.txt`（生成在游戏可执行文件所在目录，若不可写则只写日志）
   - `...\ue4ss\UE4SS.log`（每行都带 `[PBZAchDiag]` 前缀）

按 **F6** 只会打印一行提示，不抓取。

## 输出示例

```
==================== PBZAchDiag v1.0.0 @ 2026-11-06 13:11:58 ====================
[ready] engine ready, press F7 to capture

---------- capture @ 2026-11-06 13:12:04 tick=17 ----------
[1] FindAllOf ok=true result=true
[2] instances=1
[3] obj=PBZAchievementSave /Engine/Transient.PBZAchievementSave_2147481898
[4] class ok=true Class /Script/ProjectPBZ.PBZAchievementSave
[5] UnlockedIds ok=true type=userdata
  count=64
   [1] ACH_001
   [2] ACH_051
   ...
[6] PlatformPending ok=true type=userdata
  pending count=0
[7] recorded=64 missing(1)=ACH_053
[8] meta ACH_066 recorded=false
[done]
```

## 结果怎么读

| 字段 | 含义 |
|---|---|
| `[5] count=` | 这个存档里已记录的成就数量 |
| `[7] missing(n)=` | 按 `ACH_001`～`ACH_065` 编号推算出的缺口（**本作成就编号连续，若版本更新导致编号变化请自行调整**） |
| `[8] meta recorded=` | 元成就 `ACH_066` 是否已写进这份存档（未完成时恒为 `false`，属正常） |
| `[6] pending count=` | 待推送队列，>0 表示有成就尚未推到 Steam |

典型结论：

- `missing` 里的那条，就是"Steam 已解锁、但这份存档没记上"的成就；
- 在同一份存档里重做该成就的条件，记录补齐后，元成就通常会在下一次判定时立即触发。

## 卸载

删除 `...\ue4ss\Mods\PBZAchDiag` 文件夹即可。也可先只删 `enabled.txt` 停用。

## 已知问题 / 注意事项

- **不要在模组加载阶段做对象查找。** UE4SS 的对象表此时尚未就绪，`FindFirstOf` / `FindAllOf` 会让游戏直接 Fatal Error。本模组因此只在按键时抓取。
- UE4SS 的数组下标**从 1 开始**，`GetArrayNum()` 返回条数。
- 早期版本会顺带查找 `PBZSaveGame` 等其它对象，同样会崩，本版已移除。
- 输出文件路径默认相对游戏进程工作目录；如果找不到 `pbz_achdiag.txt`，直接看 `UE4SS.log`，或把 `main.lua` 顶部的 `OUT_FILE` 改成绝对路径。

## 免责声明

本工具只读，不修改存档与账号数据。使用第三方加载器存在导致游戏崩溃的风险，请自行备份存档。本项目与游戏开发商、发行商及 Steam 无任何关联。

## English

A read-only UE4SS Lua mod for **Phantom Blade Zero**. It dumps the achievement record stored inside your current save (`PBZAchievementSave.UnlockedIds`) plus the pending platform queue (`PlatformPending`) while the game is running, because the `.sav` file itself is encrypted.

Useful when Steam shows e.g. 65/66 and the final achievement never unlocks: it tells you exactly which achievement is missing from the save that the meta-achievement check reads.

**Install:** drop the `PBZAchDiag` folder into `...\ue4ss\Mods\`, make sure `enabled.txt` exists.

**Use:** load a save, wait a few seconds, press **F7**. Output goes to `pbz_achdiag.txt` next to the game executable and to `UE4SS.log` (lines prefixed `[PBZAchDiag]`).

It never writes the save and never calls unlock/reset APIs.

## License

MIT，见 [LICENSE](LICENSE)。
