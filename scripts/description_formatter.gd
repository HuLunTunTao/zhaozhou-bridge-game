class_name DescriptionFormatter
extends RefCounted
## 技能描述格式化 + 关键词词典：把五行流转系统中的元素反应专有名词包装为
## "超链接"样式（蓝色 + 下划线 + 可点击），并提供关键词→解释查询给 tooltip。
## 五行属性本身（金/木/水/火/土）不在此列。


const HYPERLINK_COLOR := "#5ab4ff"

## 关键词 → 解释。Dictionary 的 keys() 顺序 == 插入顺序，单次扫描按此顺序尝试匹配，
## 因此长词必须排在短词前面（目前全部 2 字，顺序无关，但约定仍然长→短）。
const ENTRIES: Dictionary = {
	# 反应系统名
	"化势": "攻击属性克制目标附着属性时触发。根据组合有不同名称与效果。",
	"逆势": "目标附着属性克制攻击属性时触发。伤害×0.80，无额外效果。",
	"同气": "攻击属性与目标附着属性相同。不触发化势，不消耗属性量，不改变附着。",
	# 制势化势（5种）
	"斫枝": "金行化势（金克木）。伤害×1.10，施加[裂伤]2回合。",
	"穿垠": "木行化势（木克土）。伤害×1.05，施加[陷裂]2回合。",
	"遏流": "土行化势（土克水）。伤害×1.00，额外造成目标最大生命×15%伤害，施加[壅水]3回合。",
	"熄燎": "水行化势（水克火）。伤害×1.10，施加[攻衰]2回合。",
	"熔铸": "火行化势（火克金）。伤害×1.00，施加[脆裂]2回合。",
	# 承势化势（5种）
	"开砺": "金行承势（金承土）。伤害×1.05，施加[剖隙]2回合。",
	"滋蔓": "木行承势（木承水）。伤害×1.00，施加[蔓缚]2回合；若结算后目标不为木属性，额外附着1层木。",
	"覆烬": "土行承势（土承火）。伤害×1.00，额外消耗1层火属性，施加[闷熄]1回合。",
	"淬锋": "水行承势（水承金）。伤害×1.05，施加[湿寒]2回合。",
	"焚延": "火行承势（火承木）。伤害×1.05，施加[灼痕]2回合；对目标周围1格造成基础攻击×0.25的火属性溅射伤害。",
	# 反应所致状态（10种）
	"裂伤": "回合结束时失去施术者基础攻击力×0.30的生命。",
	"陷裂": "移动时前2格每格额外消耗4点行动力。",
	"壅水": "行动开始时不执行固有属性回补。",
	"攻衰": "造成的伤害降低20%。",
	"脆裂": "下一次受到的伤害额外提高20%。",
	"剖隙": "受到击退/冲撞/地形撞击时额外承受施术者基础攻击力×0.50的伤害。",
	"开隙": "受到击退/冲撞/地形撞击时额外承受施术者基础攻击力×0.50的伤害。",
	"蔓缚": "最大可移动格数-1。",
	"闷熄": "下回合开始时不能额外获得火属性量。",
	"湿寒": "下回合行动力恢复值降低15%。",
	"灼痕": "回合结束时失去施术者基础攻击力×0.25的生命。",
	# 其他技能状态（4种）
	"稳步": "进入浅水额外消耗-4，本回合第一次被击退时距离-1。",
	"迟步": "每移动1格额外消耗2点行动力。",
	"迟滞": "每移动1格额外消耗2点行动力。",
	"护持": "首次受到的伤害-12，不能被拖拽或击退超过1格。",
}


## 把纯文本描述转换为 BBCode：命中的关键词包装为
## [url=kw][color=蓝][u]kw[/u][/color][/url]。
## RichTextLabel 在 bbcode_enabled=true 时识别 [url]，点击触发 meta_clicked，
## 悬停触发 meta_hover_started/ended 信号。
static func format(text: String) -> String:
	if text.is_empty():
		return text
	var result := ""
	var i := 0
	var n := text.length()
	var keys: Array = ENTRIES.keys()
	while i < n:
		var matched := false
		for kw in keys:
			var kl: int = kw.length()
			if i + kl <= n and text.substr(i, kl) == kw:
				result += "[url=%s][color=%s][u]%s[/u][/color][/url]" % [kw, HYPERLINK_COLOR, kw]
				i += kl
				matched = true
				break
		if not matched:
			result += text[i]
			i += 1
	return result


## 查询关键词解释；未知关键词返回空串。
static func get_description(keyword: String) -> String:
	return ENTRIES.get(keyword, "")


static func has_keyword(keyword: String) -> bool:
	return ENTRIES.has(keyword)
