shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

uniform vec4 jet_color : source_color = vec4(0.45, 0.65, 1.0, 0.7);
uniform float pulse_strength : hint_range(0.0, 1.0) = 1.0;
uniform float effect_opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	float travel = clamp(1.0 - UV.y, 0.0, 1.0);
	float edge = 0.55 + 0.45 * pow(clamp(abs(dot(normalize(NORMAL), normalize(VIEW))), 0.0, 1.0), 0.6);
	float fade = pow(1.0 - travel, 0.7);
	float pulse = mix(1.0, 0.8 + 0.2 * sin(travel * 22.0 - TIME * 31.0 + UV.x * 9.0), pulse_strength);
	ALBEDO = jet_color.rgb * (1.1 + pulse * 0.35);
	ALPHA = jet_color.a * fade * edge * pulse * effect_opacity;
}
