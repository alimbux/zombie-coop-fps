shader_type canvas_item;
// Нуар-фильтр для каждой половины экрана: всё в оттенках серого,
// красным остаётся только кровь. Плюс контраст, зерно плёнки и виньетка.

uniform float contrast = 1.3;
uniform float grain_amount = 0.07;
uniform float vignette = 0.5;
uniform float seed_offset = 0.0;

float rand(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	lum = clamp((lum - 0.5) * contrast + 0.5, 0.0, 1.0);

	// Насколько пиксель «красный»: только кровь в игре имеет такой цвет.
	float redness = clamp((c.r - max(c.g, c.b)) * 3.0, 0.0, 1.0);
	vec3 blood = vec3(max(c.r, 0.6), 0.0, 0.02);
	vec3 col = mix(vec3(lum), blood, redness);

	float n = rand(UV * 731.0 + vec2(TIME * 17.0 + seed_offset, TIME * 9.0)) - 0.5;
	col += n * grain_amount;

	vec2 d = UV - 0.5;
	col *= 1.0 - dot(d, d) * vignette * 2.0;

	COLOR = vec4(col, 1.0);
}
