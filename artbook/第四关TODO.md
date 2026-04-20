# 第四关《敞肩试汛》实现 TODO

对照 `第四关数值.txt` 设计稿，当前 `scenes/levels/level1-4/` 的缺口清单。
当前完成度约 99%：7 大步骤全部打钩 + 3 个品质调优（激流桥缘只击退触发 / 淤泥留印 -2AP / Progress 面板章节 banner + 结算摘要）。剩下：§3 桥心观察位（低优先级，可跳）、§6 站位实测微调（需可玩性反馈）。

---

## 1. 资源文件缺失

### 1.1 单位资源 `data/units/`
目前全在脚本里用 `_mud_data / _dark_data / _drift_data / _survey_data / _craftsman_data` duplicate 生成，需要独立 `.tres`：

- [x] `flood_spear.tres`（洪锋：HP 98 / ATK 24 / 水×2）
- [x] `siltmare.tres`（泥沙魇：HP 84 / ATK 18 / 土×2）
- [x] `pier_gnawer.tres`（桥台噬者：HP 116 / ATK 22 / 土×2）
- [x] `flood_driftwood_pack.tres`（漂木群·洪水版：HP 58 / ATK 20 / 木×2）
- [x] `wrathful_flood.tres`（怒水 Boss：HP 360 / ATK 24 / 水×2，fixed_position）

### 1.2 技能资源 `data/skills/`
- [x] `fs_torrent_ram.tres`（激湍冲桥：line_2，水，击退 1，命中桥台扣稳定 —— 扣稳定逻辑已在 `_on_skill_executed` 接入）
- [x] `sm_mire_steps.tres`（浊潮覆步：近战，土，附着 1）
- [x] `pg_gnaw_pier.tres`（啮台重凿：近战 1.05 倍，土，附着 1）
- [x] `wf_overturn_bridge.tres`（翻潮压桥：Boss 全局技能，扣低稳定桥台 + 边缘激流 —— 效果 1/2 已接入，效果 3 激流压区延后到第 5 步）

### 1.3 关卡配置资源 `data/stages/chapter1_stage4/`
- [x] `stage_config.tres`
- [x] `bridge_stability_config.tres`（初始 12 / 6 / 6，上限 6）
- [x] `side_arch_config.tres`（四小拱 anchor 偏移；绝对坐标仍运行时算）
- [x] `wave_spawns.tres`（把硬编码的 `get_wave_config()` 迁出）

---

## 2. 脚本行为缺失（`level1-4.gd`）

### 2.1 Boss 怒水
- [x] 目前挂的是 `lc_divider_mark_arc`，换成自己的 `wf_overturn_bridge`
- [x] 被动「洪心难撼」：伤害上限已在 `_on_stage_hp_changed` 实现 ✅
- [x] 被动「怒涛拍面」：敌方回合结束对桥面最近未护持我方造成 ATK×0.5 无属性伤害（`_boss_slam_deck`）
- [x] 全泄时 Boss 伤害 -15% 已有 ✅
- [x] 主动「翻潮压桥」三效果全接入：较低桥台 -1 + open≤1 时整桥 -1 + 桥面上下缘激流桥缘 1 回合

### 2.2 敌人专属被动
- [x] 洪锋·被动「涌锋」：本回合首次移动 +1 格 —— 敌方回合 AP 重置后给 +`move_cost_per_tile` 的 AP（`_apply_flood_spear_surge` via call_deferred）
- [x] 泥沙魇·被动「淤行」
  - blocked 转换（小拱上行动结束 → blocked）：并入 `_resolve_enemy_pressure` 的 `漂木群·洪水版 or 泥沙魇` 分支
  - 淤泥格 2 回合：`SiltTile` 在泥沙魇非小拱行动结束时 spawn；进入 -4AP
  - 停留结束 → 下回合首次移动 -2AP：两队回合开始后 `_apply_silt_lingering_penalty(team_index)` 扣 AP
- [x] 桥台噬者·被动「蚀基」：相邻桥台扣稳定 ✅（单位名已统一为「桥台噬者」）
- [x] 漂木群·被动「塞肩」：回合结束位于小拱则 blocked ✅

### 2.3 敌方 AI 优先级
`_get_ai_context()` 返回 `priority_targets: Dictionary[unit_name → Array[Unit]]`，AIBrain._pick_target 命中即返回：
- [x] 洪锋：桥面我方（按到弱桥台距离排序） > fallback 最近
- [x] 泥沙魇：运石工（按到最近关闭小拱距离排序） > fallback 最近
- [x] 桥台噬者：全我方（按到弱桥台距离排序） > fallback 最近
- [x] 漂木群：沿固定洪道直线（`hazard_charge` + `drift_directions`） ✓ 原有

### 2.4 波次
设计稿为 T2/3/4/5/7/9/11 共 7 波，当前 `get_wave_config()` 只有 5 波（T3/5/6/7/9）：
- [x] 补 T2（洪锋 ×1，`watch_north_2`）
- [x] 补 T4（桥台噬者 ×1，`near_left_pier_west`）
- [x] 补 T11（洪锋 ×1，`near_right_pier_east`）
- [x] T7 改为「洪锋 + 漂木群」双刷
- [x] T9 改为「桥台噬者」
- [x] 复核敌方总量：洪锋×5（初 2 + T2/T7/T11）/ 泥沙魇×2（初 1 + T5）/ 桥台噬者×2（T4/T9）/ 漂木群×2（T3/T7）/ 怒水×1 ✅ 对齐设计稿

### 2.5 名称对齐
当前脚本里混用了旧名字（桥台侵蚀、泥沙流、漂木群洪水版），设计稿是（桥台噬者、泥沙魇、漂木群·洪水版）。建议：
- [x] 统一单位 `unit_name`（包括 `桥台侵蚀→桥台噬者`、`泥沙流→泥沙魇`、`漂木群洪水版→漂木群·洪水版`、`洪峰→洪锋`），`_resolve_enemy_pressure` / `_get_ai_context` 的匹配字符串也同步

---

## 3. 特殊地格 / 地图交互

`movement_manager.gd` / tileset 层缺：
- [x] **激流桥缘（RapidEdgeTile）**：**仅**被击退/拖拽进入时 12 伤（主动走过不扣，符合设计稿语义）；Boss 翻潮压桥效果 3 在桥面上下缘生成 1 回合；`_apply_rapid_edge_if_present` 在 skill_executed 后扫击退落格
- [x] **淤泥格（SiltTile）**：泥沙魇行动结束在非小拱格生成 2 回合，进入 -4 AP，停留结束下回合 -2 AP（`_apply_silt_lingering_penalty`）
- [ ] **桥心观察位**：仅标记用，不加数值 —— 低优先级
- [x] **小拱节点可视化（SmallArchTile）**：closed/open/blocked 3 色；`_set_arch_state` 统一入口同步

---

## 4. 开场与叙事

对比 `level1-1.gd::_on_phase_changed_for_onboarding`，第四关基本没叙事；现补：
- [x] 开场剧情对话 —— 已有 `1-4-begin.ogv` pre 视频（`CUTSCENE_DATA`），进关自动播放
- [x] 首回合教学 —— `_onboarding_hints()` 在 PLAYING 阶段分段 Notify 提示 Boss 机制 / 开肩 / 抢修 AP / 伤害上限
- [x] BRIEFING 目标面板文字润色（`get_objectives_text()` 改写，胜负条件各扩到 3-4 条有叙事感的句子）
- [x] 胜利结算剧情 —— 已有 `1-4-end.ogv` post 视频；`chapter_1` flag + `li_chun_stage_title = 安桥者` 写入 `Progress.level_clear_summary`

---

## 5. 结算与存档

设计稿 §9：
- [x] 通关后写入 `chapter_1` 旗标（`Progress.chapter_flags` + `set_chapter_flag`）
- [x] 结算项记录：通关回合数、剩余整桥/左/右桥台稳定、开启小拱数、是否全泄击破、称号——全存在 `Progress.level_clear_summary["关卡1-4"]`
- [x] 章节完成画面：复用 `assets/cutscenes/level1-4/1-4-end.ogv`（`CUTSCENE_DATA` 已接线）

---

## 6. 站位与开局

对照设计稿 §7，当前 `_spawn_allies` / `_spawn_enemies` 站位是拍脑袋放的：
- [ ] 工匠 A/B 前置桥台、工匠 C 桥心 —— 需要核对实际地图坐标
- [ ] 运石工 A/B 分别靠近左后/右后小拱 —— 坐标偏移 `Vector2i(-1,1)/(1,1)` 需实测
- [ ] 开局敌方：怒水 ×1 + 洪锋 ×2 + 泥沙魇 ×1（当前是怒水 ×1 + 洪锋 ×2 + 泥沙流 ×1，OK 但名称未统一）

---

## 7. 建议推进顺序

1. ~~**先补单位/技能 .tres 资源**（机械工作，无风险）~~ ✅
2. ~~**统一单位命名**，避免后续分支判断错~~ ✅
3. ~~**Boss 专属技能与「怒涛拍面」**（关系胜负节奏）~~ ✅
4. ~~**波次补齐**（关系难度曲线）~~ ✅
5. ~~**特殊地格**（改动 movement_manager，较大）~~ ✅ SmallArch / Silt / RapidEdge
6. ~~**AI 优先级**（需要改 AI 行为模板）~~ ✅
7. ~~**开场/教学/结算叙事**（最后补，锁定完成态）~~ ✅ BRIEFING + Notify 教学 + Progress.chapter_flags

### 额外完成（不在原 TODO 内）
- 洪锋 / 漂木群·洪水版 冲撞直线命中左右桥台 → 对应桥台稳定值 -1（设计稿 §1.3 要求，挂在 `_on_skill_executed`）
- 调试兜底：Ctrl+1..8 强制触发各失败条件 + Boss 技能 + 强杀 Boss（`_debug_force_defeat` / `_cast_overturn_bridge` / `_boss_slam_deck` / `_debug_force_boss_kill`，仅 `OS.is_debug_build()` 下启用）
