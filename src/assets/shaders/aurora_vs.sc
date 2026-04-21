$input a_position, a_texcoord0
$output v_texcoord0, v_world_pos

#include <bgfx_shader.sh>

uniform vec4 u_time;          // x = time in seconds
uniform vec4 u_aurora_params; // x = global intensity

void main() {
    vec3 pos = a_position;
    float t = u_time.x;

    // Bottom of the ribbon (uv.v = 0) oscillates more than the top (uv.v = 1)
    float wave_weight = 1.0 - a_texcoord0.y * 0.65;

    // 3 superimposed frequencies for organic motion
    float w1 = sin(pos.x * 0.025 + t * 0.70) * 5.0;
    float w2 = sin(pos.x * 0.055 - t * 1.10) * 2.5;
    float w3 = sin(pos.x * 0.120 + t * 0.45) * 1.2;

    pos.y += (w1 + w2 + w3) * wave_weight;

    vec4 world_pos = mul(u_model[0], vec4(pos, 1.0));
    gl_Position = mul(u_viewProj, world_pos);

    v_texcoord0 = a_texcoord0;
    v_world_pos = world_pos.xyz;
}
