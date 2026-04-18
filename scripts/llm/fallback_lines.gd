class_name LLMFallbackLines
## LLM 调用失败时的兜底台词池。语气与"老监工"人设保持一致——
## 用一句话掩饰过去，不让玩家看到难看的报错。
##
## 用法：
##   var line := LLMFallbackLines.random()

const LINES: Array[String] = [
	"嘿，老天爷给我打了个盹，先自个儿盘算盘算。",
	"嗓子哑了，缓口气再说。",
	"你眼睛比老汉我亮，自己琢磨吧。",
	"工地嘈杂，没听清——你拿主意。",
	"老把式今儿懒得开口，照你的意思来。",
	"心里有数就行，不必事事问我。",
	"桥是你建的，怎么走你说了算。",
	"我去看一眼石料，等会儿再聊。",
	"风太大，话飞了。",
	"老胳膊老腿不灵光，先歇会儿。",
	"且看着办，老汉信你。",
	"嗯……让我再瞅瞅。",
]


## 从池中随机取一句。
static func random() -> String:
	if LINES.is_empty():
		return ""
	return LINES[randi() % LINES.size()]
