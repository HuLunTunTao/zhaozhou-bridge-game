class_name DescriptionFormatter
extends RefCounted
## 技能描述格式化：把五行流转系统中的元素反应专有名词包装为"超链接"样式
## （蓝色 + 下划线 + 可点击），用于 RichTextLabel 显示。
## 五行属性本身（金/木/水/火/土）不在此列。


const HYPERLINK_COLOR := "#5ab4ff"

## 按长度降序：多字词先尝试匹配。当前全部 2 字，顺序主要留给未来扩展。
const KEYWORDS: Array[String] = [
	"化势", "逆势", "同气",
	"斫枝", "穿垠", "遏流", "熄燎", "熔铸",
	"开砺", "滋蔓", "覆烬", "淬锋", "焚延",
	"裂伤", "陷裂", "壅水", "攻衰", "脆裂",
	"灼痕", "蔓缚", "湿寒", "闷熄", "开隙",
	"稳步", "迟步", "迟滞", "护持",
]


## 把纯文本描述转换为 BBCode：命中的关键词包装为 [url=kw][color=蓝][u]kw[/u][/color][/url]。
## RichTextLabel 在 bbcode_enabled=true 时识别 [url]，点击触发 meta_clicked 信号。
static func format(text: String) -> String:
	if text.is_empty():
		return text
	var result := ""
	var i := 0
	var n := text.length()
	while i < n:
		var matched := false
		for kw in KEYWORDS:
			var kl := kw.length()
			if i + kl <= n and text.substr(i, kl) == kw:
				result += "[url=%s][color=%s][u]%s[/u][/color][/url]" % [kw, HYPERLINK_COLOR, kw]
				i += kl
				matched = true
				break
		if not matched:
			result += text[i]
			i += 1
	return result
