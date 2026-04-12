shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 0.0, 0.3);
uniform float outline_width : hint_range(1.0, 10.0, 0.5) = 2.0;

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
				total += texture(TEXTURE, UV + vec2(x, y) * ps).a;
			}
		}
		float avg = total / max(samples, 1.0);
		float edge = smoothstep(0.0, 0.5, avg);
		if (edge > 0.01) {
			COLOR = vec4(outline_color.rgb, outline_color.a * edge);
		} else {
			COLOR = col;
		}
	}
}
