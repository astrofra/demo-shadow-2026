$input vWorldPos, vNormal, vTangent, vBinormal, vTexCoord0, vTexCoord1, vLinearShadowCoord0, vLinearShadowCoord1, vLinearShadowCoord2, vLinearShadowCoord3, vSpotShadowCoord, vProjPos, vPrevProjPos

// HARFANG(R) Copyright (C) 2022 Emmanuel Julien, NWNC HARFANG. Released under GPL/LGPL/Commercial Licence, see licence.txt for details.
#include <forward_pipeline.sh>

// Surface attributes

uniform vec4 uColorCenter; // x,y,z : color value at the center of the sky (screenspace, see uPosCenter)
uniform vec4 uColorSides; // x,y,z : color value at the boundaries of the sky (screenspace)
uniform vec4 uPosCenter; // x,y : position of the so-called "center" (screenspace)
uniform vec4 uPowSky;
uniform vec4 uFog; // x = fog contribution (1.0 default)
uniform vec4 uSkyParams; // x=noise_strength, y=star_brightness, z=star_rotation_speed (rad/s)

SAMPLER2D(uSkyNoise, 0); // greyscale fBm noise for atmospheric variation
SAMPLER2D(uSkyStars, 1); // equirectangular starfield

// Cross-platform atan2: HLSL's atan() is single-arg only, use the half-tangent identity
float sky_atan2(float y, float x) {
	return 2.0 * atan(y / (sqrt(x*x + y*y) + x + 1e-6));
}

float map(float value, float min1, float max1, float min2, float max2) {
  return min2 + (value - min1) * (max2 - min2) / (max1 - min1);
}

float ComputeUnifiedVignette(vec2 uv, vec2 center) {
	vec2 delta = uv - center;
	delta.x *= uResolution.x / max(uResolution.y, 1.0);
	delta.y *= 1.15;

	float radial = dot(delta, delta);
	return 1.0 - smoothstep(0.08, 0.82, radial);
}

vec3 ApplyUnifiedVignette(vec3 color, vec2 uv, vec2 center) {
	float vignette = ComputeUnifiedVignette(uv, center);
	vec3 edge_tint = vec3(0.86, 0.72, 0.98);
	vec3 tinted_color = color * mix(edge_tint, vec3(1.0, 1.0, 1.0), vignette);
	float edge_shade = mix(0.58, 1.0, vignette);
	return tinted_color * edge_shade;
}

float ComputeLuminance(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

vec3 ConvergeDarkColor(vec3 color) {
	vec3 shadow_tint = vec3(21.0 / 255.0, 1.0 / 255.0, 31.0 / 255.0);
	vec3 black_floor = shadow_tint * 0.025;
	float color_luminance = max(ComputeLuminance(color), 1e-4);
	float tint_luminance = max(ComputeLuminance(shadow_tint), 1e-4);
	vec3 luminance_preserved_tint = shadow_tint * (color_luminance / tint_luminance);
	float near_black = 1.0 - smoothstep(0.0, 0.15, color_luminance);
	float tint_amount = pow(near_black, 2.6) * 0.24;
	color = mix(color, luminance_preserved_tint, tint_amount);
	return max(color, black_floor);
}

//
vec3 DistanceFog(vec3 pos, vec3 color) {
	if (uFogState.y == 0.0)
		return color;

	float k = clamp((pos.z - uFogState.x) * uFogState.y, 0.0, 1.0);
	k *= uFog.x;
	return mix(color, uFogColor.xyz, k);
}

// Entry point of the forward pipeline default uber shader (Phong and PBR)
void main() {
	//
#if DEPTH_ONLY != 1
	vec3 view = mul(u_view, vec4(vWorldPos, 1.0)).xyz;
	vec3 P = vWorldPos; // fragment world pos
	vec3 V = normalize(GetT(u_invView) - P); // world space view vector
	vec3 N = sign(dot(V, vNormal)) * normalize(vNormal); // geometry normal

	vec3 R = reflect(-V, N); // view reflection vector around normal

	float NdotV = clamp(dot(N, V), 0.0, 0.99);

	vec3 color = uColorCenter.xyz;

	// jitter
#if FORWARD_PIPELINE_AAA
	vec4 jitter = texture2D(uNoiseMap, mod(gl_FragCoord.xy, vec2(64, 64)) / vec2(64, 64));
#else // FORWARD_PIPELINE_AAA
	vec4 jitter = vec4_splat(0.);
#endif // FORWARD_PIPELINE_AAA

	// color = vec3(1.0, 0.0, 1.0);
	vec2 sky_screen_coords = gl_FragCoord.xy / uResolution.xy;
	float dist_from_sky_center = distance(sky_screen_coords, uPosCenter.xy);
	dist_from_sky_center = map(dist_from_sky_center, uPowSky.y, uPowSky.z, 0.0, 1.0);
	dist_from_sky_center = clamp(dist_from_sky_center, 0.0, 1.0);
	dist_from_sky_center = pow(dist_from_sky_center, uPowSky.x) * uPowSky.w;
	color = mix(uColorCenter, uColorSides, dist_from_sky_center);
	color = ApplyUnifiedVignette(color, sky_screen_coords, uPosCenter.xy);

	// Atmospheric noise: domain-warped spherical mapping (SideFX Sky Field Noise - Lattice Warp)
	// base_uv: equirectangular projection of the view direction, fixed to world space
	vec3 D = -V;
	float drift = uClock.x * 0.002; // imperceptibly slow drift
	vec2 base_uv = vec2(
		sky_atan2(D.x, D.z) / 6.28318 + 0.5,
		asin(clamp(D.y, -0.999, 0.999)) / 3.14159 + 0.5);

	// Lattice warp: two noise taps at decorrelated offsets give independent X/Y displacement
	// (keeps the sky wispy and avoids the grid artefacts of direct sampling)
	float wx = texture2D(uSkyNoise, base_uv * 1.40 + vec2(0.18, 0.33) + drift        ).r * 2.0 - 1.0;
	float wy = texture2D(uSkyNoise, base_uv * 1.85 + vec2(0.73, 0.51) + drift * 0.55).r * 2.0 - 1.0;

	// Third tap at warped coordinates gives the final cloud density
	float cloud = texture2D(uSkyNoise, base_uv * 2.0 + vec2(wx, wy) * 0.22).r;

	// Stage 1 — linear contrast: flatten darks, lift brights
	cloud = clamp((cloud - 0.38) * 2.1 + 0.5, 0.0, 1.0);

	// Stage 2 — S-curve (smoothstep): hardens edges, creates defined wisps
	cloud = cloud * cloud * (3.0 - 2.0 * cloud);

	// Stage 3 — power sharpening: uSkyParams.w in [0,1], 0=off, 1=strong
	//   w=0.0 -> pow 1.0 (identity)   w=0.6 -> pow 2.2   w=1.0 -> pow 3.0
	cloud = pow(cloud, 1.0 + uSkyParams.w * 2.0);

	color *= 0.78 + cloud * uSkyParams.x * 0.40;

	color = DistanceFog(view, color);
	color = ConvergeDarkColor(color);

	// Stars: slowly rotating around Y axis, fade below horizon
	float rot   = uClock.x * uSkyParams.z;
	float rot_c = cos(rot), rot_s = sin(rot);
	vec3 D_rot  = vec3(D.x * rot_c + D.z * rot_s, D.y, -D.x * rot_s + D.z * rot_c);
	vec2 star_uv = vec2(
		sky_atan2(D_rot.x, D_rot.z) / 6.28318 + 0.5,
		asin(clamp(D_rot.y, -0.999, 0.999)) / 3.14159 + 0.5);
	float star_val  = texture2D(uSkyStars, star_uv).r * 0.25;
	float star_fade = smoothstep(-0.05, 0.28, D.y);
	color += vec3_splat(star_val * star_fade * uSkyParams.y);
#endif // DEPTH_ONLY != 1

	float opacity = 1.0;

#if DEPTH_ONLY != 1
#if FORWARD_PIPELINE_AAA_PREPASS
	vec3 N_view = mul(u_view, vec4(N, 0)).xyz;
	vec2 velocity = vec2(vProjPos.xy / vProjPos.w - vPrevProjPos.xy / vPrevProjPos.w);
	gl_FragData[0] = vec4(N_view.xyz, vProjPos.z);
	gl_FragData[1] = vec4(velocity.xy, 0.5, 0.);
#else // FORWARD_PIPELINE_AAA_PREPASS
	// incorrectly apply gamma correction at fragment shader level in the non-AAA pipeline
#if FORWARD_PIPELINE_AAA != 1
	float gamma = 2.2;
	color = pow(color, vec3_splat(1. / gamma));
#endif // FORWARD_PIPELINE_AAA != 1

	gl_FragColor = vec4(color, opacity);
#endif // FORWARD_PIPELINE_AAA_PREPASS
#else
	gl_FragColor = vec4_splat(0.0); // note: fix required to stop glsl-optimizer from removing the whole function body
#endif // DEPTH_ONLY
}
