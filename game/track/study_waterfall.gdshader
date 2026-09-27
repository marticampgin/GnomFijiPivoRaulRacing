shader_type spatial;
render_mode cull_disabled;
uniform float motion_strength = 1.0;
void fragment() {
    float t = TIME * motion_strength;
    float stream = sin(UV.x * 90.0 + sin(UV.y * 7.0) * 1.2);
    float foam = pow(abs(sin(UV.y * 38.0 - t * 9.0 + UV.x * 6.0)), 10.0);
    float edge = smoothstep(0.0, 0.18, UV.x) * smoothstep(0.0, 0.18, 1.0 - UV.x);
    ALBEDO = mix(vec3(0.18, 0.58, 0.65), vec3(0.77, 0.9, 0.87), clamp(0.45 + stream * 0.15 + foam * 0.2 + (1.0 - edge) * 0.14, 0.0, 1.0));
    ROUGHNESS = 0.35;
    SPECULAR = 0.45;
}
