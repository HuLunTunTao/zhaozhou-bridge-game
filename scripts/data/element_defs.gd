class_name ElementDefs
extends RefCounted
## 五行属性的全局颜色、名称与标志符号。供 UI、popup、notification 共用。


const COLORS: Dictionary = {
	Enums.Element.NONE:  Color8(140, 147, 161),   # 灰
	Enums.Element.METAL: Color8(255, 215, 70),    # 金黄
	Enums.Element.WOOD:  Color8(110, 220, 110),   # 草绿
	Enums.Element.WATER: Color8(90, 180, 255),    # 天蓝
	Enums.Element.FIRE:  Color8(230, 70, 60),     # 红
	Enums.Element.EARTH: Color8(200, 150, 80),    # 棕黄
}

const NAMES: Dictionary = {
	Enums.Element.NONE:  "无",
	Enums.Element.METAL: "金",
	Enums.Element.WOOD:  "木",
	Enums.Element.WATER: "水",
	Enums.Element.FIRE:  "火",
	Enums.Element.EARTH: "土",
}

## 带标志符号的属性显示名，用于 UI 标签。
const LOGOS: Dictionary = {
	Enums.Element.NONE:  "无",
	Enums.Element.METAL: "◇金",
	Enums.Element.WOOD:  "✿木",
	Enums.Element.WATER: "≈水",
	Enums.Element.FIRE:  "✦火",
	Enums.Element.EARTH: "▦土",
}


static func get_color(e: Enums.Element) -> Color:
	return COLORS.get(e, Color.WHITE)


static func element_name(e: Enums.Element) -> String:
	return NAMES.get(e, "?")


static func element_logo(e: Enums.Element) -> String:
	return LOGOS.get(e, "?")


## 返回带颜色的属性标签文本（如 "◇金×2"），适合 Label 显示。
## 若属性为 NONE 或 amount <= 0，返回空字符串。
static func element_tag(e: Enums.Element, amount: int) -> String:
	if e == Enums.Element.NONE or amount <= 0:
		return ""
	return "%s%d" % [LOGOS.get(e, "?"), amount]


## BBCode 便捷包装：返回 "[color=#rrggbb]text[/color]"，供 RichTextLabel 使用。
static func bbcode(e: Enums.Element, text: String) -> String:
	return "[color=#%s]%s[/color]" % [get_color(e).to_html(false), text]
