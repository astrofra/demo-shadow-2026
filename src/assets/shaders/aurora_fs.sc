$input v_texcoord0, v_world_pos

#include <bgfx_shader.sh>

uniform vec4 u_time;          // x = time in seconds
uniform vec4 u_aurora_params; // x = global intensity

void main() {
    float t   = u_time.x;
    vec2  uv  = v_texcoord0;

    // --- Vertical fade ---
    // Frayed at the bottom, soft fade at the top
    float fade_v = smoothstep(0.0, 0.18, uv.y) * (1.0 - smoothstep(0.62, 1.0, uv.y));

    // --- Animated horizontal bands (curtain effect) ---
    float b1 = 0.5 + 0.5 * sin(uv.x * 14.0 + t * 1.40);
    float b2 = 0.5 + 0.5 * sin(uv.x *  8.0 - t * 0.85 + 1.3);
    float b3 = 0.5 + 0.5 * sin(uv.x * 26.0 + t * 2.10);
    float bands = b1 * 0.50 + b2 * 0.35 + b3 * 0.15;

    // --- High-frequency shimmer ---
    float shimmer = 0.65 + 0.35
        * sin(uv.x * 42.0 + t * 3.9)
        * sin(t * 2.6 + uv.x * 9.5);

    // --- Color palette (ref: Yellowknife aurora photo) ---
    // Real physics: green = oxygen ~100km, pink/magenta = nitrogen lower edge + upper oxygen
    vec3 c_dark   = vec3(0.02, 0.12, 0.10);  // deep teal-black (fade out)
    vec3 c_green  = vec3(4/255, 16/255, 44/255); // vec3(0.18, 0.72, 0.42);  // main aurora green (dominant body)
    vec3 c_bright = vec3(0.55 * 0.8, 0.95 * 1.1, 0.70 * 0.8);  // white-green at intensity peaks
    vec3 c_pink   = vec3(0.82, 0.40, 0.65);  // rose-magenta fringe (edges, lower base)

    // Green body: dark -> green -> white-green as bands intensify
    vec3 color = mix(c_dark,  c_green,  smoothstep(0.10, 0.52, bands));
    color      = mix(color,   c_bright, smoothstep(0.65, 0.92, bands));

    // Pink fringe: concentrated at the bottom of the ribbon (low uv.y)
    // and in thin fast-moving streaks across the curtain
    float pink_base   = (1.0 - smoothstep(0.0, 0.38, uv.y)) * bands;
    float pink_streak = b3 * (1.0 - b1 * 0.6);  // thin high-freq streaks inside green
    float pink_amount = clamp(pink_base * 0.92 + pink_streak * 0.30, 0.0, 1.0);
    color = mix(color, c_pink, pink_amount);

    // Top blends into sky color (#04102C)
    vec3 c_sky = vec3(0.016, 0.063, 0.173);
    float top_fade = smoothstep(0.48, 1.0, uv.y);
    color = mix(color, c_sky, top_fade * 0.72);

    // --- Final alpha ---
    float alpha = fade_v * shimmer * bands * u_aurora_params.x;
    alpha = clamp(alpha, 0.0, 1.0);

    // Premultiplied output (same convention as volume_fs.sc)
    gl_FragColor = vec4(color * alpha, alpha);
}
