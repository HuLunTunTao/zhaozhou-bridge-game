# 05 -- 资源唯一化（Make Unique）

> 本章介绍 Godot 中 Resource（资源）的共享机制，以及如何使用"唯一化（Make Unique）"功能避免意外修改到其他场景中的数据。

---

## 5.1 为什么需要关注资源唯一化

在 Godot 中，**Resource 是默认共享的**。当多个节点引用同一个 `.tres` 文件（或同一个内嵌资源）时，对其中任意一个节点上的该资源进行修改，都会影响所有引用方。

举例：假设关卡 A 和关卡 B 中的两个 Unit 节点都引用了 `data/units/hero_li_chun.tres`。如果你在关卡 A 中打开这个 Unit 的 Inspector，把 `max_hp` 从 130 改成了 200，那么关卡 B 中的李春也会变成 200 HP -- 因为它们指向的是**同一份数据文件**。

这在多人协作时尤其危险：你以为只改了自己的关卡，实际上影响了所有使用这个资源的场景。

---

## 5.2 两种资源引用方式

在 Godot Inspector 中，一个 Resource 类型的属性有两种存在形式：

| 形式 | 特征 | 修改影响范围 |
|------|------|-------------|
| **外部引用（External .tres）** | Inspector 中显示文件路径（如 `hero_li_chun.tres`） | 修改会影响所有引用此文件的节点 |
| **内联资源（Inline SubResource）** | Inspector 中显示类型名（如 `UnitData`），没有文件路径 | 修改只影响当前场景 |

### 如何判断

选中节点后，在 Inspector 中点击资源属性的下拉箭头：

- 如果菜单中出现 **"保存 (Save)"** 或 **"另存为 (Save As)"**，说明是外部 `.tres` 文件
- 如果菜单中出现 **"Make Unique"**，说明当前是共享引用（可能是外部文件，也可能是同一场景内的共享内联资源）

---

## 5.3 Make Unique 操作方法

当你需要让某个节点拥有一份**独立的**资源副本时：

1. 在场景树中选中目标节点
2. 在 Inspector 中找到要唯一化的资源属性（例如 `Unit Data`）
3. 点击资源属性右侧的**下拉箭头**（小三角图标）
4. 在弹出菜单中选择 **"Make Unique"**

此操作会将该资源属性从"引用外部文件"变为"内联副本"。之后你对这个副本的任何修改都不会影响原始 `.tres` 文件或其他引用方。

> ⚠️ 注意: Make Unique 后，资源变成了场景内的内联 SubResource。如果你之后还想把修改后的数据共享给其他场景，需要使用下拉菜单中的 **"另存为 (Save As)"** 将其导出为新的 `.tres` 文件。

---

## 5.4 各类资源的唯一化指南

### SpriteFrames（单位动画）

**运行时已自动处理。** Unit 场景的 `_ready()` 中调用了 `_make_sprite_frames_unique()`，会在游戏运行时自动 `duplicate()` AnimatedSprite2D 的 SpriteFrames 资源。因此，运行时各单位实例的动画颜色互不影响。

**但在编辑器中需要注意：** 如果你在编辑器中直接修改某个 Unit 实例的 AnimatedSprite2D 的 SpriteFrames（例如调整帧速率、替换帧图片），这些修改会影响源场景 `unit.tscn` 中的 SpriteFrames。

建议：
- 通常**不需要**在关卡场景中修改 SpriteFrames
- 如果确实需要让某个单位使用不同的动画，先对 SpriteFrames 做 Make Unique，再进行修改

### UnitData（单位数据）

这是设计师最常接触的资源类型。

| 场景 | 推荐做法 |
|------|----------|
| 使用标准配置的角色（例如标准的李春） | 直接引用 `data/units/hero_li_chun.tres`，**不要修改** |
| 使用标准角色但需要微调属性（例如某关的精英泥鬼 HP 更高） | 对 Unit Data 做 **Make Unique**，然后修改副本 |
| 创建全新角色 | 在 Inspector 中新建 UnitData（内联），或者在 `data/units/` 中创建新的 `.tres` 文件 |

> ❌ 常见错误: 在关卡中选中一个引用了 `hero_li_chun.tres` 的 Unit，直接在 Inspector 中修改了 `max_hp`，导致所有关卡中的李春属性都被改了。发生这种情况时，用 `Ctrl+Z` 撤销，或在 Git 中还原 `data/units/hero_li_chun.tres` 文件。

### SkillData（技能数据）

与 UnitData 的规则相同。技能数据通过 UnitData 的 `skills` 数组引用。

| 场景 | 推荐做法 |
|------|----------|
| 标准技能 | 直接引用 `data/skills/` 下的 `.tres` 文件 |
| 需要微调技能参数（例如某关卡中技能 AP 消耗不同） | 先对 UnitData 做 Make Unique，再对 skills 数组中的对应 SkillData 做 Make Unique |

> ⚠️ 注意: SkillData 嵌套在 UnitData 的 skills 数组中。如果你只对 UnitData 做了 Make Unique 但没有对其中的 SkillData 也做 Make Unique，修改 SkillData 仍然会影响原始技能文件。需要**逐层唯一化**。

### StyleBox / Theme 等 UI 资源

关卡设计师通常不需要修改 UI 资源。但如果需要为某个关卡定制特殊的 UI 样式：

1. 找到对应的 UI 节点（如 StatusPanel 下的某个 Label）
2. 在 Inspector 中找到 Theme Override 相关的属性
3. 对 StyleBox 或 Font 资源做 **Make Unique**
4. 修改唯一化后的副本

---

## 5.5 什么时候不需要 Make Unique

- **只读取数据、不修改**：如果你只是将 `.tres` 文件拖拽到 Unit Data 属性上作为引用，而不修改其中的字段值，则无需唯一化
- **创建新的内联资源**：在 Inspector 中通过 "New UnitData" 创建的资源本身就是内联的 SubResource，天然独立于其他场景
- **运行时自动唯一化的资源**：如 SpriteFrames，代码中已处理

---

## 5.6 实操示例：为某关卡创建精英敌人

假设你想在关卡 1-5 中放置一个 HP 更高的坍岸泥鬼（标准版 HP=92，精英版 HP=150）：

1. 在 Units 节点下实例化一个 `unit.tscn`，命名为 `EliteMudWraith`
2. 将 `data/units/bank_mud_wraith.tres` 拖拽到 **Unit Data** 属性上
3. 点击 Unit Data 右侧的**下拉箭头** -> 选择 **"Make Unique"**
4. 展开 Unit Data，将 `max_hp` 从 `92` 改为 `150`
5. （可选）修改 `unit_name` 为 `"精英坍岸泥鬼"`

此时 Inspector 中的 Unit Data 不再显示 `bank_mud_wraith.tres` 文件名，而是显示 `UnitData`（内联），说明已经是独立副本。

> 💡 提示: 如果你打算在多个关卡中复用这个精英泥鬼，建议使用下拉菜单中的 "另存为 (Save As)" 将其保存为 `data/units/bank_mud_wraith_elite.tres`，这样其他关卡也可以引用。

---

## 5.7 排查资源共享问题

如果你怀疑某个资源被意外共享，可以通过以下方式验证：

### 方法一：检查 Inspector 中的资源标识

选中节点，在 Inspector 中点击资源属性的下拉箭头。如果显示了文件路径（如 `res://data/units/hero_li_chun.tres`），说明是外部共享资源。

### 方法二：查看 .tscn 文件中的资源引用

用文本编辑器打开 `.tscn` 文件，搜索资源引用：

- `[ext_resource ...  path="res://data/units/hero_li_chun.tres"]` -- 外部引用，共享
- `[sub_resource type="Resource" id="..."]` 后面跟着具体字段值 -- 内联资源，独立

### 方法三：使用 Git diff 检查

修改后运行 `git diff`，查看哪些文件被改动了。如果你只想改关卡场景但看到 `data/units/xxx.tres` 也被改了，说明你意外修改了共享资源。

---

## 5.8 唯一化检查清单

每次在 Inspector 中修改资源属性前，确认以下事项：

- [ ] 我要修改的是**内联资源**还是**外部 .tres 文件**？
- [ ] 如果是外部文件，我是否**有意**修改所有引用方的数据？
- [ ] 如果只想修改当前关卡的数据，是否已经做了 **Make Unique**？
- [ ] 如果资源有嵌套（如 UnitData 中的 SkillData），嵌套的资源是否也需要唯一化？
- [ ] 修改后用 `git diff` 确认，是否只有预期的文件被改动？

---

下一章: [06-Git 工作流](06-git-workflow.md) | 上一章: [04-关卡参数](04-level-parameters.md)
