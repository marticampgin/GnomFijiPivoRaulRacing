shader_type spatial;
render_mode cull_disabled, unshaded;
uniform float motion_strength = 1.0;
varying vec3 world_position;
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
    float t = TIME * motion_strength;
    float wave = sin(world_position.x * 0.13 + world_position.z * 0.37 + sin(world_position.x * 0.07) * 1.8 + t * 0.35);
    float cross_wave = sin(world_position.x * 0.29 - world_position.z * 0.09 + sin(world_position.z * 0.11) + t * 0.27);
    float drift = sin(world_position.x * 0.041 + world_position.z * 0.053 - t * 0.1);
    ALBEDO = vec3(0.04, 0.31, 0.37) + vec3(0.009, 0.027, 0.024) * (wave * 0.45 + cross_wave * 0.3 + drift * 0.25);
}
