class_name VoiceMapping
## 16 个 NPC 的火山 TTS 音色映射（豆包语音合成 2.0 系列）。
## 微调；想替换的字段直接改 voice 即可。
##
## 音色挑选思路：
##   - 主角李春：文人匠师 → 儒雅逸辰
##   - 工匠：中年稳重老把式 → 大壹
##   - 测量工：中老年测量师，方法稳健爱用数字 → 解说小明
##   - 拟人化怪物：按"贪婪/阴冷/冲锋/守旧/讥讽/呓语/旋转/BOSS"七种基调挑差异化音色
##
## 用法：
##   var cfg := VoiceMapping.get_voice(unit_id)
##   tts_client.synthesize(text, cfg.voice, cfg.model)

const DEFAULT_MODEL := "seed-tts-2.0-expressive"

const VOICES: Dictionary = {
	# ─── 友方 ───
	"hero_li_chun": {
		"voice": "zh_male_ruyayichen_uranus_bigtts",   # 儒雅逸辰 2.0
		"label": "儒雅逸辰",
		"note": "李春：文人匠师，沉稳半文白",
	},
	"craftsman_guard": {
		"voice": "zh_male_dayi_uranus_bigtts",         # 大壹 2.0
		"label": "大壹",
		"note": "工匠：中年稳重，沉默认死理",
	},
	"survey_worker": {
		"voice": "zh_male_jieshuoxiaoming_uranus_bigtts",# 解说小明 2.0
		"label": "解说小明",
		"note": "测量工：中老年测量师，按尺绳报数字、有点絮叨",
	},
	# ─── 敌方 ───
	"bank_mud_wraith": {
		"voice": "zh_male_xuanyijieshuo_uranus_bigtts",# 悬疑解说 2.0
		"label": "悬疑解说",
		"note": "坍岸泥流：缓慢诡异、贪婪",
	},
	"dark_current": {
		"voice": "zh_male_gaolengchenwen_uranus_bigtts",# 高冷沉稳 2.0
		"label": "高冷沉稳",
		"note": "暗涌：阴冷低语、断续",
	},
	"drift_log_pack": {
		"voice": "zh_male_baqiqingshu_uranus_bigtts",  # 霸气青叔 2.0
		"label": "霸气青叔",
		"note": "浮木群：沉重撞击感",
	},
	"flood_driftwood_pack": {
		"voice": "zh_male_lubanqihao_uranus_bigtts",   # 鲁班七号 2.0
		"label": "鲁班七号",
		"note": "漂木群·洪水版：机械狂暴",
	},
	"flood_spear": {
		"voice": "zh_male_sunwukong_uranus_bigtts",    # 猴哥 2.0
		"label": "猴哥",
		"note": "洪锋：冲锋吼叫，活力",
	},
	"heavy_pier_statue": {
		"voice": "zh_male_dongfanghaoran_uranus_bigtts",# 东方浩然 2.0
		"label": "东方浩然",
		"note": "重墩石像：沉重念咒",
	},
	"high_arch_phantom": {
		"voice": "zh_male_yizhipiannan_uranus_bigtts", # 译制片男 2.0
		"label": "译制片男",
		"note": "高拱幻影：戏剧化讥讽",
	},
	"old_method_supervisor": {
		"voice": "zh_male_silang_uranus_bigtts",# 四郎 2.0
		"label": "四郎 2.0",
		"note": "旧制监工：守旧长者教训口气",
	},
	"pier_gnawer": {
		"voice": "zh_male_cixingjieshuonan_uranus_bigtts", # 磁性解说男 2.0
		"label": "磁性解说男",
		"note": "桥台噬者：低沉冷酷",
	},
	"rule_guard_head": {
		"voice": "zh_male_tangseng_uranus_bigtts",     # 唐僧 2.0
		"label": "唐僧",
		"note": "循旧匠首：迂腐唠叨守古法",
	},
	"siltmare": {
		"voice": "zh_female_popo_uranus_bigtts",       # 婆婆 2.0
		"label": "婆婆",
		"note": "泥沙魇：呓语含糊",
	},
	"whirl_pool": {
		"voice": "zh_female_ganmaodianyin_uranus_bigtts", # 感冒电音姐姐 2.0
		"label": "感冒电音",
		"note": "水旋：怪异打转、重复音",
	},
	"wrathful_flood": {
		"voice": "zh_male_qingcang_uranus_bigtts",     # 擎苍 2.0
		"label": "擎苍",
		"note": "怒水：BOSS 沉重宣告",
	},
}

## 阵营兜底：查不到 unit_id 时的通用音色。
const FALLBACK_ALLY := {
	"voice": "zh_male_youyoujunzi_uranus_bigtts",      # 悠悠君子 2.0
	"label": "悠悠君子",
	"note": "友方兜底",
}

const FALLBACK_ENEMY := {
	"voice": "zh_male_qingcang_uranus_bigtts",         # 擎苍 2.0
	"label": "擎苍",
	"note": "敌方兜底",
}


## 取一个 unit_id 的音色配置。返回 { voice, label, note }；
## 调用方再补 model（默认 DEFAULT_MODEL）。
static func get_voice(unit_id: String, camp: int = 0) -> Dictionary:
	if VOICES.has(unit_id):
		return VOICES[unit_id]
	if camp == Enums.Camp.ENEMY:
		return FALLBACK_ENEMY
	return FALLBACK_ALLY
