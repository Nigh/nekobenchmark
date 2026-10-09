shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 outer_color : source_color;
uniform vec4 inner_color : source_color;
uniform bool scoring = false;
uniform float progress = 0.0;

void fragment() {
	vec2 point = UV - vec2(0.5);
	float radius = length(point);
	if (radius > 0.495) { discard; }
	if (radius > 0.455) {
		float angle = mod(atan(point.x, -point.y) + 6.283185, 6.283185) / 6.283185;
		ALBEDO = (scoring || angle < progress) ? inner_color.rgb : outer_color.rgb * 0.25;
	} else if (radius > 0.5 / 1.12) {
		discard;
	} else {
		vec3 color = radius <= 0.25 / 1.12 ? inner_color.rgb : outer_color.rgb;
		ALBEDO = scoring ? color : mix(color, vec3(0.35), 0.45);
	}
}
