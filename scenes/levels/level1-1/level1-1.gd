extends BaseLevel
## 第一关《踏勘洨河》

# ── 预加载技能 ──
var _sk_rule_strike: SkillData = preload("res://data/skills/lc_rule_strike.tres")
var _sk_wedge: SkillData = preload("res://data/skills/lc_wedge_bank_probe.tres")
var _sk_stone: SkillData = preload("res://data/skills/lc_cast_stone_arrest_flow.tres")
var _sk_read_water: SkillData = preload("res://data/skills/lc_read_water_fix_site.tres")
var _sk_staff: SkillData = preload("res://data/skills/sw_staff_end_strike.tres")
var _sk_survey: SkillData = preload("res://data/skills/sw_field_measure_site.tres")
var _sk_mallet: SkillData = preload("res://data/skills/cg_mallet_strike.tres")
var _sk_guard: SkillData = preload("res://data/skills/cg_guard_the_works.tres")

# ── 占位纹理（运行时生成，避免导入依赖）──
var _placeholder_tex: Texture2D

# ── 单位引用 ──
var _li_chun: Node2D
var _survey_a: Node2D
var _survey_b: Node2D
var _craftsman_a: Node2D
var _craftsman_b: Node2D


func get_teams_config() -> Array:
	_li_chun = $"Entities/Units/LiChun"
	_survey_a = $"Entities/Units/SurveyWorkerA"
	_survey_b = $"Entities/Units/SurveyWorkerB"
	_craftsman_a = $"Entities/Units/CraftsmanA"
	_craftsman_b = $"Entities/Units/CraftsmanB"
	return [
		{
			"name": "玩家队伍",
			"faction": "好人",
			"controller": "player",
			"units": [_li_chun],
		},
		{
			"name": "辅助队伍",
			"faction": "好人",
			"controller": "player",
			"units": [_survey_a, _survey_b, _craftsman_a, _craftsman_b],
		},
	]


func get_objectives_text() -> Dictionary:
	return {
		"victory": [
			"- 完成 3 个勘测点",
			"- 李春在候选桥位执行「相水定址」",
			"- 至少 1 名测量工进入撤离区并结束回合",
		],
		"defeat": [
			"- 李春死亡",
			"- 两名测量工全部死亡",
			"- 超过第 10 回合仍未完成撤离",
		],
	}


func _on_level_ready() -> void:
	_placeholder_tex = _create_placeholder_texture()

	# ── 李春 ──
	assign_skills(_li_chun as Unit, [_sk_rule_strike, _sk_wedge, _sk_stone, _sk_read_water] as Array[SkillData])
	setup_unit_stats(_li_chun as Unit, "李春", 130, 24, 100, 8, Enums.Element.NONE, 0, true)

	# ── 测量工 ──
	assign_skills(_survey_a as Unit, [_sk_staff, _sk_survey] as Array[SkillData])
	setup_unit_stats(_survey_a as Unit, "测量工", 80, 12, 85, 10)
	_set_placeholder_sprite(_survey_a as Unit)

	assign_skills(_survey_b as Unit, [_sk_staff, _sk_survey] as Array[SkillData])
	setup_unit_stats(_survey_b as Unit, "测量工", 80, 12, 85, 10)
	_set_placeholder_sprite(_survey_b as Unit)

	# ── 工匠 ──
	assign_skills(_craftsman_a as Unit, [_sk_mallet, _sk_guard] as Array[SkillData])
	setup_unit_stats(_craftsman_a as Unit, "工匠", 110, 18, 90, 9)
	_set_placeholder_sprite(_craftsman_a as Unit)

	assign_skills(_craftsman_b as Unit, [_sk_mallet, _sk_guard] as Array[SkillData])
	setup_unit_stats(_craftsman_b as Unit, "工匠", 110, 18, 90, 9)
	_set_placeholder_sprite(_craftsman_b as Unit)


## 生成人形占位纹理，尺寸与李春精灵帧匹配（256x256，人形居中）。
func _create_placeholder_texture() -> ImageTexture:
	var size := 256
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var head := Color(0.45, 0.9, 0.6)
	var body := Color(0.35, 0.8, 0.5)
	var limb := Color(0.25, 0.7, 0.4)
	# 人形居中，约 40x80 像素，底部对齐 y≈200（脚着地）
	var cx: int = size / 2  # 128
	var foot_y := 200
	# 头 (12x12)
	_fill_rect(img, cx - 6, foot_y - 80, 12, 12, head)
	# 躯干 (24x32)
	_fill_rect(img, cx - 12, foot_y - 66, 24, 32, body)
	# 左臂 (8x28)
	_fill_rect(img, cx - 20, foot_y - 62, 8, 28, limb)
	# 右臂 (8x28)
	_fill_rect(img, cx + 12, foot_y - 62, 8, 28, limb)
	# 左腿 (10x30)
	_fill_rect(img, cx - 11, foot_y - 32, 10, 32, limb)
	# 右腿 (10x30)
	_fill_rect(img, cx + 1, foot_y - 32, 10, 32, limb)
	return ImageTexture.create_from_image(img)


func _fill_rect(img: Image, x0: int, y0: int, w: int, h: int, color: Color) -> void:
	for x in range(maxi(x0, 0), mini(x0 + w, img.get_width())):
		for y in range(maxi(y0, 0), mini(y0 + h, img.get_height())):
			img.set_pixel(x, y, color)


## 用占位纹理替换单位的动画精灵。
func _set_placeholder_sprite(unit: Unit) -> void:
	var visual := unit.get_node_or_null("Visual")
	if not visual is AnimatedSprite2D:
		return
	var sprite := visual as AnimatedSprite2D
	var frames := SpriteFrames.new()
	for anim_name in ["SE_idle", "SW_idle", "NE_idle", "NW_idle",
			"SE_walk", "SW_walk", "NE_walk", "NW_walk"]:
		frames.add_animation(anim_name)
		frames.add_frame(anim_name, _placeholder_tex)
	sprite.sprite_frames = frames
	sprite.play(&"SE_idle")
