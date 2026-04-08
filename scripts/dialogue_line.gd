class_name DialogueLine
extends Resource
## 单条对话数据。开发者可在代码中用 DialogueLine.create() 快捷构建，
## 也可在编辑器中作为 .tres 资源手动配置。

## 说话者名称（留空则隐藏名称栏）
@export var speaker: String = ""
## 对话文本（支持 BBCode）
@export_multiline var text: String = ""
## 说话者头像（留空则不显示头像）
@export var portrait: Texture2D = null
## 头像位于左侧还是右侧
@export_enum("left", "right") var portrait_side: String = "left"


## 快捷构造函数
static func create(
	p_speaker: String,
	p_text: String,
	p_portrait: Texture2D = null,
	p_side: String = "left"
) -> DialogueLine:
	var line := DialogueLine.new()
	line.speaker = p_speaker
	line.text = p_text
	line.portrait = p_portrait
	line.portrait_side = p_side
	return line
