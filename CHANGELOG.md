# Changelog

## 1.0.0 — 2026-11-06

首个公开版本。

- 按 F7 读取 `PBZAchievementSave.UnlockedIds` 与 `PlatformPending`；
- 自动比对 `ACH_001`～`ACH_066`，输出 `missing(...)` 缺口摘要；
- 同时写入输出文件与 `UE4SS.log`（`[PBZAchDiag]` 前缀）；
- 移除加载期的对象查找（该行为会导致 Fatal Error），改为按键触发；
- 仅做只读属性访问，不调用任何解锁 / 重置接口。
