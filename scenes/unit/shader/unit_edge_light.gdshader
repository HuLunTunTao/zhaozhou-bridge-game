shader_type canvas_item;
// 描边/发光 shader —— 支持 SpriteSheet (AtlasTexture)。
//
// 解决两个问题：
//   1. 帧污染：采样 clamp 到 frame_uv_rect，不会越界到相邻帧。
//   2. 边缘裁剪：vertex 外扩 quad，描边不被 sprite 边界截断。
//
// 需要 GDScript 在帧变化时更新 frame_uv_rect uniform。

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 0.0, 0.3);
uniform float outline_width : hint_range(1.0, 10.0, 0.5) = 2.0;
// 当前帧在 atlas 中的 UV 矩形: (min_u, min_v, max_u, max_v)
// 由 UnitVisual 在帧切换时设置。默认 (0,0,1,1) 覆盖整张纹理。
uniform vec4 frame_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);

void fragment() {
	vec4 col = texture(TEXTURE, UV);

	if (col.a > 0.0) {
		COLOR = col;
	} else {
		vec2 ps = TEXTURE_PIXEL_SIZE;
		float w = outline_width;
		float total = 0.0;
		float samples = 0.0;
		for (float x = -w; x <= w; x += 1.0) {
			for (float y = -w; y <= w; y += 1.0) {
				float d = length(vec2(x, y));
				if (d > w || d == 0.0) { continue; }
				samples += 1.0;
				vec2 sample_uv = UV + vec2(x, y) * ps;
				// clamp 到帧矩形内，防止采样到相邻帧
				sample_uv = clamp(sample_uv, frame_uv_rect.xy, frame_uv_rect.zw);
				total += texture(TEXTURE, sample_uv).a;
			}
		}
		float avg = total / max(samples, 1.0);
		float edge = smoothstep(0.0, 0.5, avg);
		if (edge > 0.01) {
			COLOR = vec4(outline_color.rgb, outline_color.a * edge);
		} else {
			COLOR = vec4(0.0);
		}
	}
}
