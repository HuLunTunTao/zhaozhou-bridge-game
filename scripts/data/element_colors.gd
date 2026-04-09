class_name ElementColors
extends RefCounted
## 五行属性的全局颜色与显示名称。供 UI、popup、notification 共用。

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


static func get_color(e: Enums.Element) -> Color:
	return COLORS.get(e, Color.WHITE)


static func get_name(e: Enums.Element) -> String:
	return NAMES.get(e, "?")


## BBCode 便捷包装：返回 "[color=#rrggbb]text[/color]"，供 RichTextLabel 使用。
static func bbcode(e: Enums.Element, text: String) -> String:
	return "[color=#%s]%s[/color]" % [get_color(e).to_html(false), text]
