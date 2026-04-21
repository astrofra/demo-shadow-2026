$input v_texcoord0, v_world_pos

#include <bgfx_shader.sh>

uniform vec4 color;
uniform vec4 u_fog_state;

SAMPLER2D(s_tex, 0);

void main() {
	vec2 centered_uv = v_texcoord0 * 2.0 - 1.0;
	float radial_fade = clamp(1.0 - dot(centered_uv, centered_uv), 0.0, 1.0);
	float world_noise = 0.55 + 0.45 * sin(v_world_pos.x * 0.21 + u_fog_state.x * 0.75) * cos(v_world_pos.z * 0.17 - u_fog_state.x * 0.65);
	float band_noise = 0.75 + 0.25 * sin((v_world_pos.x + v_world_pos.z) * 0.08 + u_fog_state.x * 0.9);
	float height_fade = 1.0 - smoothstep(0.0, 2.2, v_world_pos.y);
	vec4 texel = texture2D(s_tex, v_texcoord0);
	float alpha = texel.a * radial_fade * radial_fade * world_noise * band_noise * height_fade * color.a;
	vec3 fog_rgb = texel.rgb * color.rgb * (0.85 + world_noise * 0.15);
	gl_FragColor = vec4(fog_rgb, alpha);
}
