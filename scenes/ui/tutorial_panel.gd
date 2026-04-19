extends CanvasLayer
## 游戏规则说明弹窗：主菜单打开。
## 内容以 5 个 Tab 呈现，元素字样使用 ElementDefs 全局颜色，化势与状态关键词
## 透过 DescriptionFormatter 生成可悬停/可点击的 url meta，用 keyword_tooltip 预览详情。

signal closed

const KEYWORD_TOOLTIP_SCENE := preload("res://scenes/ui/keyword_tooltip.tscn")
const TOOLTIP_MOUSE_OFFSET := Vector2(14.0, -8.0)

@onready var _tabs: TabContainer = %Tabs
@onready var _basics_body: RichTextLabel = %BasicsBody
@onready var _turn_body: RichTextLabel = %TurnBody
@onready var _elements_body: RichTextLabel = %ElementsBody
@onready var _status_body: RichTextLabel = %StatusBody
@onready var _tips_body: RichTextLabel = %TipsBody

var _tooltip: PanelContainer = null
var _tooltip_title: Label = null
var _tooltip_body: RichTextLabel = null


func _ready() -> void:
	layer = 95
	_ensure_tooltip()
	_populate_all()
	for body in [_basics_body, _turn_body, _elements_body, _status_body, _tips_body]:
		body.meta_hover_started.connect(_on_meta_hover_started)
		body.meta_hover_ended.connect(_on_meta_hover_ended)
	for button in find_children("*", "BaseButton", true, false):
		UiSounds.bind_button(button as BaseButton)


func _unhandled_input(event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel"):
		_close()


func _process(_delta: float) -> void:
	if _tooltip != null and _tooltip.visible:
		_position_tooltip_at_mouse()


# ─────────────────────────────────────────────
# Tooltip
# ─────────────────────────────────────────────

func _ensure_tooltip() -> void:
	if _tooltip != null:
		return
	_tooltip = KEYWORD_TOOLTIP_SCENE.instantiate()
	add_child(_tooltip)
	_tooltip_title = _tooltip.get_node("VBox/Title") as Label
	_tooltip_body = _tooltip.get_node("VBox/Body") as RichTextLabel


func _on_meta_hover_started(meta: Variant) -> void:
	var keyword := str(meta)
	var desc := DescriptionFormatter.get_description(keyword)
	if desc.is_empty():
		return
	_tooltip_title.text = keyword
	_tooltip_body.text = desc
	_tooltip.reset_size()
	_tooltip.visible = true
	_tooltip.move_to_front()
	_position_tooltip_at_mouse()


func _on_meta_hover_ended(_meta: Variant) -> void:
	if _tooltip != null:
		_tooltip.visible = false


func _position_tooltip_at_mouse() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	var mouse := get_viewport().get_mouse_position()
	var tsize := _tooltip.size
	var pos := Vector2(
		mouse.x + TOOLTIP_MOUSE_OFFSET.x,
		mouse.y - tsize.y + TOOLTIP_MOUSE_OFFSET.y
	)
	if pos.x + tsize.x > vp_size.x:
		pos.x = mouse.x - tsize.x - TOOLTIP_MOUSE_OFFSET.x
	if pos.y < 0.0:
		pos.y = mouse.y + 16.0
	pos.x = clampf(pos.x, 0.0, maxf(0.0, vp_size.x - tsize.x))
	pos.y = clampf(pos.y, 0.0, maxf(0.0, vp_size.y - tsize.y))
	_tooltip.global_position = pos


# ─────────────────────────────────────────────
# 文案
# ─────────────────────────────────────────────

func _populate_all() -> void:
	_basics_body.text = _build_basics()
	_turn_body.text = _build_turn()
	_elements_body.text = _build_elements()
	_status_body.text = _build_status()
	_tips_body.text = _build_tips()


func _elem(e: Enums.Element) -> String:
	## 带图案 + 颜色的元素标签，用于 BBCode 文本。
	return ElementDefs.bbcode(e, ElementDefs.element_logo(e))


func _hdr(text: String) -> String:
	## 段落标题：深琥珀色 + 前导竖线。不使用加粗（像素字体加粗后笔画糊在一起）。
	return "[color=#7a4a14]▎%s[/color]" % text


func _sub(text: String) -> String:
	## 子标题或内嵌术语强调：中等琥珀色。同样不使用加粗。
	return "[color=#9c6a26]%s[/color]" % text


# Tab 1：目标与回合
func _build_basics() -> String:
	var s := ""
	s += _hdr("胜负条件") + "\n"
	s += "每关开始前会弹出目标面板，列出本关具体的胜利条件和失败条件。多数关卡不是「击败全部敌人」就能过。\n\n"
	s += "常见胜利类型：\n"
	s += "• 完成全部勘测点。由指定单位用指定技能触发激活。\n"
	s += "• 关键单位到达指定位置，并在该格结束回合。\n"
	s += "• 守住若干大回合，阻止敌方推进。\n\n"
	s += "常见失败类型：\n"
	s += "• 李春阵亡。\n"
	s += "• 关卡点名的其他关键角色全部倒下。\n"
	s += "• 超过关卡规定的最大大回合数。\n\n"
	s += "战斗中随时可以通过顶部的目标按钮调出目标面板。\n\n"

	s += _hdr("回合推进") + "\n"
	s += "战斗按队伍轮流行动，不是按单位穿插。己方队伍完整走一遍后，轮到敌方；所有队伍都走完一遍，大回合计数 +1。顶部显示当前是谁的回合、第几个大回合。\n\n"
	s += "己方回合期间，你可以按任意顺序操作己方单位——一个单位动到一半切到另一个再回来都可以，只要 AP 没用完。右下角「结束回合」把控制权交给下一支队伍。\n\n"
	s += "每名单位在自己的队伍回合开始时：AP 重置为上限；按固有属性回补一定元素量。部分状态会修改这两项（见「状态与界面」）。"
	return s


# Tab 2：基础操作
func _build_turn() -> String:
	var s := ""
	s += _hdr("选中与移动") + "\n"
	s += "左键点己方单位完成选中。底部状态栏立即展开它的全部信息，地图上高亮它本回合能到达的格子。\n\n"
	s += "再左键点任意高亮格，单位沿最短路径走过去，每经过一格扣除该格地形规定的 AP。若当前 AP 不足以到达某格，该格不会出现在高亮范围里。\n\n"

	s += _hdr("释放技能") + "\n"
	s += "选中单位后，点状态栏右侧的技能图标：地图显示该技能的蓝色可释放范围。鼠标移到候选点上会预览作用范围（红=攻击，绿=辅助，黄=交互）。左键点确认释放，扣除 AP 后结算效果。\n\n"
	s += "技能不一定要打敌人——空地也能作为目标。瞄准时想换个落点，按右键或 Esc 取消当前瞄准再选。技能必中，没有闪避、没有暴击。伤害可以在释放前预览。\n\n"

	s += _hdr("技能后继续行动") + "\n"
	s += "释放完技能只要 AP 还有，单位保持选中，可以继续移动或再放别的技能。点状态栏的「移动」按钮切回走路模式。每回合移动与技能次数原则上不设上限，AP 用完就结束。个别单位（例如友军跟随者）数据里额外写了每回合次数上限，状态栏会显示剩余次数。\n\n"

	s += _hdr("取消与查看") + "\n"
	s += "右键或 Esc 取消当前选中或技能瞄准。左键点非己方或本回合已行动的单位只展开信息栏，不会把它当成操作对象。\n\n"

	s += _hdr("镜头与设置") + "\n"
	s += "方向键、鼠标边缘、右键拖拽都可以移动镜头；滚轮缩放。右上角齿轮打开设置、存档、返回主菜单。"
	return s


# Tab 3：伤害与五行流转
func _build_elements() -> String:
	var s := ""
	s += _hdr("基础伤害") + "\n"
	s += "基础伤害 = 施术者攻击力 × 技能伤害系数。例如攻击 20、系数 1.2，基础伤害 24。本作无暴击、无闪避、无命中率。\n\n"

	s += _hdr("伤害结算顺序") + "\n"
	s += "在基础伤害之上，按以下顺序修正：\n"
	s += "1. 乘上本次触发化势的倍率（见下）。\n"
	s += "2. 施术者带" + DescriptionFormatter.format("攻衰") + "再乘 0.8。\n"
	s += "3. 目标带" + DescriptionFormatter.format("脆裂") + "再乘 1.2，脆裂在本次命中后消耗。\n"
	s += "4. 目标带" + DescriptionFormatter.format("护持") + "扣除固定 12 点伤害，护持在本次命中后消耗。\n"
	s += "5. 部分化势追加一段额外伤害（如" + DescriptionFormatter.format("遏流") + "追加目标最大 HP 的 15%，上限为攻击力的 2 倍）。\n\n"

	s += _hdr("五行属性") + "\n"
	s += "每个单位有两个属性字段：" + _sub("固有属性") + "（天生的）和" + _sub("当前属性") + "（身上此刻挂着的）。每个技能也带一个属性。五行共五种，界面颜色固定：\n"
	s += "   " + _elem(Enums.Element.METAL) + "    " + _elem(Enums.Element.WOOD) + "    " + _elem(Enums.Element.WATER) + "    " + _elem(Enums.Element.FIRE) + "    " + _elem(Enums.Element.EARTH) + "\n\n"

	s += _hdr("五行流转") + "\n"
	s += "技能属性与目标当前属性产生五行关系时，即进入" + DescriptionFormatter.format("五行流转") + "。按关系类型分三种，触发的具体反应统称为" + DescriptionFormatter.format("化势") + "：\n\n"

	s += _sub("制势（攻击属性克目标当前属性）") + "\n"
	s += DescriptionFormatter.format("• 金 打 木 — 斫枝 ×1.10，挂 2 回合裂伤") + "\n"
	s += DescriptionFormatter.format("• 木 打 土 — 穿垠 ×1.05，挂 2 回合陷裂") + "\n"
	s += DescriptionFormatter.format("• 土 打 水 — 遏流 追加伤害，挂 3 回合壅水") + "\n"
	s += DescriptionFormatter.format("• 水 打 火 — 熄燎 ×1.10，挂 2 回合攻衰") + "\n"
	s += DescriptionFormatter.format("• 火 打 金 — 熔铸 挂 2 回合脆裂") + "\n\n"

	s += _sub("承势（目标当前属性生攻击属性）") + "\n"
	s += DescriptionFormatter.format("• 金 击 土 — 开砺 ×1.05，挂 2 回合剖隙") + "\n"
	s += DescriptionFormatter.format("• 水 击 金 — 淬锋 ×1.05，挂 2 回合湿寒") + "\n"
	s += DescriptionFormatter.format("• 木 击 水 — 滋蔓 挂 2 回合蔓缚") + "\n"
	s += DescriptionFormatter.format("• 火 击 木 — 焚延 ×1.05，挂 2 回合灼痕") + "\n"
	s += DescriptionFormatter.format("• 土 击 火 — 覆烬 额外消耗 1 点附着，挂 1 回合闷熄") + "\n\n"

	s += DescriptionFormatter.format("逆势") + "：目标当前属性克攻击属性，伤害 ×0.80，无附加效果。\n"
	s += DescriptionFormatter.format("同气") + "：两者属性相同，不进入五行流转，不消耗附着，伤害正常结算。\n\n"

	s += _hdr("元素附着") + "\n"
	s += "当技能属性 ≠ 目标当前属性、且技能附着量 > 0，会发生属性替换：双方量大的一方保留为当前属性，量为两者之差；相等则当前属性清空。带附着的技能即使命中「无属性」目标也会把自己的属性附着上去。很多时候第一击只是挂属性，第二击才兑现化势。"
	return s


# Tab 4：地形与机关
func _build_status() -> String:
	var s := ""
	s += _hdr("地形移动消耗") + "\n"
	s += "地图由等距格子构成，单格 AP 消耗按地形决定：\n"
	s += "• 土地 / 石路 — 1 AP\n"
	s += "• 草地 — 2 AP\n"
	s += "• 水中石 — 3 AP\n"
	s += "• 浅水 — 7 AP\n"
	s += "• 深水 — 不可进入\n\n"
	s += "走一段路的总消耗是沿途地形 AP 的累加。AP 不够走到某格时，该格不会高亮。\n\n"

	s += _hdr("水属性与单位限制") + "\n"
	s += "部分单位（例如水栖敌人）在数据里标记为「仅限水面移动」，只能走水相关地块。绝大多数普通单位无法进入深水。\n\n"

	s += _hdr("机关地块") + "\n"
	s += "关卡里会出现几类有额外规则的地块：\n\n"
	s += _sub("勘测点") + "：由指定单位用指定技能在该格释放即可激活，计入任务目标。\n\n"
	s += _sub("桥位") + "：李春的「相水定址」技能必须在这里释放，用于推进章节剧情。\n\n"
	s += _sub("撤离点") + "：关键单位走进撤离点[i]并在该格结束回合[/i]（而不是经过）才算撤离成功。\n\n"
	s += "这些地块在地图上有视觉标识，鼠标悬停可看说明文字。\n\n"

	s += _hdr("关卡阶段与回合上限") + "\n"
	s += "部分关卡分阶段。触发特定条件（完成某勘测点、抵达某位置、击败某 boss 等）后，敌人刷新、新目标解锁或地形变化。阶段切换会在屏幕中部弹通知告知。\n\n"
	s += "有些关卡还有大回合上限。超时未完成任务直接判失败，具体回合数写在目标面板里。"
	return s


# Tab 5：状态与界面
func _build_tips() -> String:
	var s := ""
	s += _hdr("顶部") + "\n"
	s += "显示当前是谁的回合、第几个大回合。\n\n"

	s += _hdr("底部状态栏") + "\n"
	s += "选中单位后展开：头像、名字、攻击力、HP 条、AP 条、当前属性、固有属性、状态 icon、1 个移动按钮加最多 5 个技能按钮。面板颜色随阵营变化：己方蓝、友军绿、敌方红。\n\n"

	s += _hdr("悬停提示") + "\n"
	s += "技能描述、化势名、状态名的蓝色下划线关键词都可以悬停查看精确数值。底部状态栏与本页提示取自同一份词典，数据不会漂。\n\n"

	s += _hdr("化势提示与伤害飘字") + "\n"
	s += "单位挨打时，伤害数字上方会短暂显示本次触发的化势名（例如「熔铸」），并标出倍率或追加伤害。未进入五行流转的普通命中只有伤害数字。\n\n"

	s += _hdr("通知栏") + "\n"
	s += "屏幕中部或顶部的文字提示会告诉你：阶段切换、任务节点达成、关键单位危险、回合临界。\n\n"

	s += _hdr("状态一览") + "\n"
	s += "战斗中出现的全部状态，鼠标停在名字上看完整数值：\n\n"
	s += _sub("减益") + "\n"
	s += DescriptionFormatter.format("• 裂伤 / 灼痕") + " — 每回合末受到施术者攻击力的 30% / 25% 伤害\n"
	s += DescriptionFormatter.format("• 陷裂") + " — 前 2 格移动每格 +4 AP\n"
	s += DescriptionFormatter.format("• 蔓缚") + " — 最大移动格数 -1\n"
	s += DescriptionFormatter.format("• 湿寒") + " — 下回合 AP 恢复 -15%\n"
	s += DescriptionFormatter.format("• 壅水") + " — 回合开始跳过固有属性回补\n"
	s += DescriptionFormatter.format("• 闷熄") + " — 下回合无法获得火属性量\n"
	s += DescriptionFormatter.format("• 攻衰") + " — 造成伤害 ×0.80\n"
	s += DescriptionFormatter.format("• 脆裂") + " — 下次受伤 ×1.20，命中一次后消耗\n"
	s += DescriptionFormatter.format("• 剖隙") + " — 被击退 / 冲撞时多承受攻击力 ×0.50 伤害\n\n"
	s += _sub("增益 / 步态") + "\n"
	s += DescriptionFormatter.format("• 护持") + " — 下次受伤 -12，抗位移（最多被推 1 格），一次后消耗\n"
	s += DescriptionFormatter.format("• 稳步") + " — 进浅水额外 -4 AP，首次被击退距离 -1\n"
	s += DescriptionFormatter.format("• 迟步 / 迟滞") + " — 每走 1 格额外 +2 AP"
	return s


# ─────────────────────────────────────────────
# 关闭
# ─────────────────────────────────────────────

func _on_close_pressed() -> void:
	_close()


func _close() -> void:
	closed.emit()
	queue_free()
