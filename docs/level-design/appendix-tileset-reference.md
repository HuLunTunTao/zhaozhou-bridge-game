# 附录 A -- 地形参考表

> 本附录汇总了项目中所有地形类型、TileType 类、移动消耗以及 Terrain 名称，供关卡设计时快速查阅。

---

## A.1 地形类型一览

以下是 `MovementManager` 中注册的所有地形类型及其对应关系：

| Terrain 名称 | 中文名 | TileType 类 | 移动消耗 | 说明 |
|--------------|--------|-------------|----------|------|
| `earth` | 泥土地 | `EarthTile` | 1 | 基础地形，消耗最低 |
| `grass` | 草地 | `GrassTile` | 2 | 比泥土消耗高一倍 |
| `stone_road` | 石板路 | `StoneRoadTile` | 1 | 与泥土相同，是人工铺设的道路 |
| `water` | 浅水 | `WaterTile` | 5 | 可通行但极慢 |
| `dark_water` | 深水 | `DarkWaterTile` | **不可通行** | 返回 `IMPASSABLE`（-1） |
| `water_stone` | 水中石 | `WaterStoneTile` | 3 | 水中的垫脚石，介于陆地和浅水之间 |
| `decora` | 装饰 | `DecoraTile` | 1 | 视觉装饰地形，不影响通行 |

### 移动消耗计算

Dijkstra 寻路算法中，角色从一个格子移动到相邻格子时，消耗的行动力 = 目标格子的地形移动消耗。

例如，角色 AP 上限 100、`move_cost_per_tile = 10` 的情况下：

> 提示: 移动消耗是 Dijkstra 寻路算法中的权重值。在 AP 模式下，进入一个格子的实际 AP 消耗 = `move_cost_per_tile`（单位基础消耗）+ (`tile_cost` - 1)（地形额外消耗，earth 和 stone_road 为 0 额外消耗，grass 为 +1 额外消耗，以此类推）。例如 AP=100、`move_cost_per_tile=8` 的李春在泥土地上每步消耗 8 AP，在草地上每步消耗 9 AP，在浅水上每步消耗 12 AP。

---

## A.2 TileType 类结构

所有地形类型都继承自基类 `TileType`（`scenes/levels/base_level/tile_types/tile_type.gd`）：

```
TileType (RefCounted)           -- 基类
├── EarthTile                   -- 泥土，消耗 1
├── GrassTile                   -- 草地，消耗 2
├── StoneRoadTile               -- 石板路，消耗 1
├── WaterTile                   -- 浅水，消耗 5
├── DarkWaterTile               -- 深水，不可通行
├── WaterStoneTile              -- 水中石，消耗 3
└── DecoraTile                  -- 装饰，消耗 1
```

### TileType 基类方法

| 方法 | 默认返回值 | 说明 |
|------|-----------|------|
| `get_movement_cost()` | `1` | 返回进入此地块的移动消耗。`-1`（`IMPASSABLE`）表示不可通行 |
| `on_enter(entity)` | （无操作） | 角色进入此地块时调用（每步移动到达后触发） |
| `on_exit(entity)` | （无操作） | 角色离开此地块时调用（每步移动出发前触发） |

> 💡 提示: 当前项目中只有 `get_movement_cost()` 被各子类覆盖，`on_enter` 和 `on_exit` 留作将来扩展（例如浅水格可以在 `on_enter` 时降低角色速度）。

---

## A.3 地形文件位置

所有地形类脚本位于：

```
scenes/levels/base_level/tile_types/
├── tile_type.gd          -- 基类
├── earth_tile.gd         -- EarthTile
├── grass_tile.gd         -- GrassTile
├── stone_road_tile.gd    -- StoneRoadTile
├── water_tile.gd         -- WaterTile
├── dark_water_tile.gd    -- DarkWaterTile
├── water_stone_tile.gd   -- WaterStoneTile
└── decora_tile.gd        -- DecoraTile
```

---

## A.4 地形注册表

地形名称到 TileType 实例的映射在 `MovementManager._setup_tile_types()` 中定义：

```gdscript
func _setup_tile_types() -> void:
    tile_type_map = {
        "earth":       EarthTile.new(),
        "grass":       GrassTile.new(),
        "stone_road":  StoneRoadTile.new(),
        "water":       WaterTile.new(),
        "dark_water":  DarkWaterTile.new(),
        "water_stone": WaterStoneTile.new(),
        "decora":      DecoraTile.new(),
    }
```

> ⚠️ 注意: 字典的键（如 `"earth"`）必须与 TileSet 中 Terrain 的名称**完全一致**。如果在 TileSet 中新增了 Terrain 但未在此处注册，系统会回退到 `earth`（消耗 1）。

---

## A.5 无 Terrain 数据时的回退行为

`MovementManager._get_tile_type()` 的回退逻辑：

1. 如果格子在 `movement_tilemaps` 中**没有地块** -> 返回 `null`（不可通行）
2. 如果格子有地块但**没有 TileData** -> 回退为 `earth`
3. 如果有 TileData 但**没有 Terrain 数据**（terrain_set < 0 或 terrain < 0）-> 回退为 `earth`
4. 如果有 Terrain 名称但**不在 tile_type_map 中** -> 回退为 `earth`

这意味着：**即使你用普通图块（非 Terrain）绘制了地表，角色也能走，但所有格子的消耗都是 1。** 要正确区分地形消耗，必须使用 Terrain 模式绘制。

---

## A.6 TileSet 资源

项目中的公共 TileSet 资源：

```
assets/battle_tile_set.tres
```

此资源定义了：
- 图块来源（spritesheet）
- 图块的纹理区域（32x32 像素）
- Terrain 集合和各 Terrain 的名称
- 等距瓦片设置（Isometric, Diamond Down, 32x16）

各关卡场景也可能使用内联的 TileSet 资源（直接嵌入 `.tscn` 文件中）。

---

## A.7 地图层命名约定

系统自动查找可行走地图层的名称顺序：

```
1. "surface z=0"
2. "Main tile map z=0"
3. "WalkableMap"
4. （回退：TileMaps 下的第一个 TileMapLayer）
```

现有关卡中使用的典型层名：

| 层名 | 用途 | z 排序 |
|------|------|--------|
| `init tile map` | 初始化底层地图 | -- |
| `surface z=0` | 地表可行走区域 | 0 |
| `decoration z=1` | 装饰物 | 1 |
| `obstacle z=2` / `Obstacle z=2` | 障碍物 | 2 |
| `items 需要画材质 z=3` | 物品层（需补充美术） | 3 |
| `thebase z=-1` | 底层 | -1 |
| `thebase z=-2` | 更底层 | -2 |

> 💡 提示: 层名中的 `z=数字` 是命名约定而非 Godot 属性。你需要在节点检查器中单独设置 **Z Index** 属性来控制实际的绘制顺序。

---

## A.8 移动消耗速查表

快速对照角色在不同地形上的每步 AP 消耗（已考虑 `move_cost_per_tile` + 地形额外消耗）：

| 地形 | 地形消耗 | 李春(mcp=8) 每步AP | 工匠(mcp=9) 每步AP | 敌方(mcp=10) 每步AP |
|------|----------|-------------------|-------------------|---------------------|
| 泥土 earth | 1 | 8 | 9 | 10 |
| 石板路 stone_road | 1 | 8 | 9 | 10 |
| 装饰 decora | 1 | 8 | 9 | 10 |
| 草地 grass | 2 | 9 | 10 | 11 |
| 水中石 water_stone | 3 | 10 | 11 | 12 |
| 浅水 water | 5 | 12 | 13 | 14 |
| 深水 dark_water | -- | 不可进入 | 不可进入 | 不可进入 |

> 提示: 每步消耗计算公式: `move_cost_per_tile + (tile_cost - 1)`。以李春为例，AP=100 在纯泥土上最多走 12 格（100/8=12.5，取整12）。在草地上最多走 11 格（100/9=11.1）。

---

返回: [目录](README.md)
