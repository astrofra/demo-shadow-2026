$input v_texcoord0

// HARFANG(R) Copyright (C) 2022 Emmanuel Julien, NWNC HARFANG. Released under GPL/LGPL/Commercial Licence, see licence.txt for details.
#include <forward_pipeline.sh>

SAMPLER2D(u_color, 0);
SAMPLER2D(u_depth, 1);
uniform vec4 uCompositingParams[4]; // [0].x: vignette start, [0].y: vignette end, [0].z: vignette strength, [0].w: circular blur strength
								  // [1].x: crt curvature, [1].y: crt mask density, [1].z: crt mask intensity

/*
	tone-mapping operators implementation taken from https://www.shadertoy.com/view/lslGzl
*/

vec3 LinearToneMapping(vec3 color, float exposure) { // 1.
	color = clamp(exposure * color, 0., 1.);
	return color;
}

vec3 SimpleReinhardToneMapping(vec3 color, float exposure) { // 1.5
	color *= exposure / (1. + color / exposure);
	return color;
}

vec3 LumaBasedReinhardToneMapping(vec3 color) {
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	float toneMappedLuma = luma / (1. + luma);
	color *= toneMappedLuma / luma;
	return color;
}

vec3 WhitePreservingLumaBasedReinhardToneMapping(vec3 color, float white) { // 2.
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	float toneMappedLuma = luma * (1. + luma / (white * white)) / (1. + luma);
	color *= toneMappedLuma / luma;
	return color;
}

vec3 RomBinDaHouseToneMapping(vec3 color) {
	color = exp(-1. / (2.72 * color + 0.15));
	return color;
}

vec3 FilmicToneMapping(vec3 color) {
	color = max(vec3(0., 0., 0.), color - vec3(0.004, 0.004, 0.004));
	color = (color * (6.2 * color + .5)) / (color * (6.2 * color + 1.7) + 0.06);
	return color;
}

float map(float value, float min1, float max1, float min2, float max2) {
  return min2 + (value - min1) * (max2 - min2) / (max1 - min1);
}

vec3 Uncharted2ToneMapping(vec3 color, float exposure) {
	float A = 0.15;
	float B = 0.50;
	float C = 0.10;
	float D = 0.20;
	float E = 0.02;
	float F = 0.30;
	float W = 11.2;
	color *= exposure;
	color = ((color * (A * color + C * B) + D * E) / (color * (A * color + B) + D * F)) - E / F;
	float white = ((W * (A * W + C * B) + D * E) / (W * (A * W + B) + D * F)) - E / F;
	color /= white;
	return color;
}

vec4 Sharpen(vec2 uv, float strength) {
	vec4 up = texture2D(u_color, uv + vec2(0, 1) / uResolution.xy);
	vec4 left = texture2D(u_color, uv + vec2(-1, 0) / uResolution.xy);
	vec4 center = texture2D(u_color, uv);
	vec4 right = texture2D(u_color, uv + vec2(1, 0) / uResolution.xy);
	vec4 down = texture2D(u_color, uv + vec2(0, -1) / uResolution.xy);

	float exposure = uAAAParams[1].x;
	up.xyz = SimpleReinhardToneMapping(up.xyz, exposure);
	left.xyz = SimpleReinhardToneMapping(left.xyz, exposure);
	center.xyz = SimpleReinhardToneMapping(center.xyz, exposure);
	right.xyz = SimpleReinhardToneMapping(right.xyz, exposure);
	down.xyz = SimpleReinhardToneMapping(down.xyz, exposure);

	vec4 res = (1.0 + 4.0 * strength) * center - strength * (up + left + right + down);
	return vec4(res.xyz, center.w);
}

vec3 ApplyTopPurpleFade(vec2 uv, vec3 color) {
	vec3 purple = vec3((0.78/7.0)/2.0, (0.56/6.0)/2.0, (0.98/4.0)/2.0);
	float fade_v = clamp(map(uv.y, 0.8, 1.0, 0.0, 1.0), 0.0, 1.0);
	fade_v = pow(fade_v, 4.0);
	return mix(color, purple, fade_v);
}

vec3 SampleCompositedColor(vec2 uv) {
	vec2 safe_uv = clamp(uv, vec2(0.0, 0.0), vec2(1.0, 1.0));
	float exposure = uAAAParams[1].x;
	vec3 color = texture2D(u_color, safe_uv).xyz;
	color = SimpleReinhardToneMapping(color, exposure);
	return ApplyTopPurpleFade(safe_uv, color);
}

vec2 WarpCRTUV(vec2 uv) {
	float curvature = max(uCompositingParams[1].x, 0.0);
	vec2 screen_pos = uv * 2.0 - vec2(1.0, 1.0);
	float radius_sq = dot(screen_pos, screen_pos);

	vec2 warped = screen_pos;
	warped.x *= 1.0 + curvature * (radius_sq * 0.18 + screen_pos.y * screen_pos.y * 0.10);
	warped.y *= 1.0 + curvature * (radius_sq * 0.22 + screen_pos.x * screen_pos.x * 0.12);

	return warped * 0.5 + vec2(0.5, 0.5);
}

float ComputeLensEdgeMask(vec2 uv) {
	// Unit circle in normalized UV space maps to an ellipse inscribed in the screen.
	vec2 ellipse_pos = uv * 2.0 - vec2(1.0, 1.0);
	float ellipse_radius = length(ellipse_pos);
	float vignette_start = uCompositingParams[0].x;
	float vignette_end = max(uCompositingParams[0].y, vignette_start + 0.0001);
	float mask = smoothstep(vignette_start, vignette_end, ellipse_radius);
	return mask * mask;
}

vec3 ApplyLensVignette(vec3 color, float lens_mask) {
	float vignette_strength = clamp(uCompositingParams[0].z, 0.0, 1.0);
	return color * (1.0 - lens_mask * vignette_strength);
}

vec3 ApplyLensEdgeDefect(vec2 uv, vec3 base_color, float lens_mask) {
	float blur_strength = max(uCompositingParams[0].w, 0.0);
	vec2 screen_pos = (uv - vec2(0.5, 0.5)) * uResolution.xy;
	vec2 radial_dir = screen_pos / max(length(screen_pos), 0.0001);
	vec2 tangent_dir = vec2(-radial_dir.y, radial_dir.x);
	vec2 radial_uv = radial_dir / uResolution.xy;
	vec2 tangent_uv = tangent_dir / uResolution.xy;

	float chroma_pixels = lens_mask * 4.5 * blur_strength;
	vec2 chroma_offset = radial_uv * chroma_pixels;
	vec3 chroma_color;
	chroma_color.r = SampleCompositedColor(uv + chroma_offset * 1.25).r;
	chroma_color.g = SampleCompositedColor(uv - chroma_offset * 0.25).g;
	chroma_color.b = SampleCompositedColor(uv - chroma_offset * 1.15).b;

	float blur_pixels = lens_mask * 7.0 * blur_strength;
	vec2 radial_blur = radial_uv * blur_pixels;
	vec2 tangent_blur = tangent_uv * blur_pixels * 0.75;
	vec3 blur_color = SampleCompositedColor(uv) * 0.24;
	blur_color += SampleCompositedColor(uv + radial_blur) * 0.16;
	blur_color += SampleCompositedColor(uv - radial_blur) * 0.16;
	blur_color += SampleCompositedColor(uv + tangent_blur) * 0.12;
	blur_color += SampleCompositedColor(uv - tangent_blur) * 0.12;
	blur_color += SampleCompositedColor(uv + radial_blur + tangent_blur) * 0.05;
	blur_color += SampleCompositedColor(uv + radial_blur - tangent_blur) * 0.05;
	blur_color += SampleCompositedColor(uv - radial_blur + tangent_blur) * 0.05;
	blur_color += SampleCompositedColor(uv - radial_blur - tangent_blur) * 0.05;

	float lens_mix = clamp(lens_mask * blur_strength, 0.0, 1.0);
	vec3 lens_color = mix(chroma_color, blur_color, lens_mix * 0.72);
	return mix(base_color, lens_color, lens_mix);
}

vec3 ApplyCRTPhotoScreen(vec2 uv, vec3 color) {
	float density = max(uCompositingParams[1].y, 0.0);
	float intensity = clamp(uCompositingParams[1].z, 0.0, 1.0);

	if (density <= 0.0 || intensity <= 0.0) {
		return color;
	}

	vec2 grid = uv * uResolution.xy * density;
	float vertical_trame = 0.5 + 0.5 * cos(grid.x * PI * 2.0);
	float horizontal_trame = 0.5 + 0.5 * cos(grid.y * PI * 2.0);
	float weave = 0.5 + 0.5 * cos((grid.x + grid.y * 0.18) * PI * 2.0);

	float luminous_mesh = pow(vertical_trame * 0.68 + horizontal_trame * 0.20 + weave * 0.12, 1.15);
	float glow_gain = mix(1.0, 0.88 + luminous_mesh * 0.24, intensity);
	float gate_gain = mix(1.0, 0.92 + horizontal_trame * 0.08, intensity * 0.65);

	return color * glow_gain * gate_gain;
}

void main() {
#if 1
	vec2 crt_uv = WarpCRTUV(v_texcoord0);
	vec4 in_sample = Sharpen(crt_uv, uAAAParams[2].y);

	vec3 color = ApplyTopPurpleFade(crt_uv, in_sample.xyz);
	float lens_mask = ComputeLensEdgeMask(crt_uv);
	if (lens_mask > 0.001) {
		color = ApplyLensEdgeDefect(crt_uv, color, lens_mask);
	}
	color = ApplyLensVignette(color, lens_mask);
	float alpha = in_sample.w;
#else
	vec2 crt_uv = WarpCRTUV(v_texcoord0);
	vec4 in_sample = texture2D(u_color, crt_uv);

	vec3 color = in_sample.xyz;
	float alpha = in_sample.w;

	float exposure = uAAAParams[1].x;
	color = SimpleReinhardToneMapping(color, exposure);
	//color = lumaBasedReinhardToneMapping(color);
	//color = FilmicToneMapping(color);
	//color = Uncharted2ToneMapping(color, exposure);
#endif

	// gamma correction
	float inv_gamma = uAAAParams[1].y;
	color = pow(color, vec3_splat(inv_gamma));
	color = ApplyCRTPhotoScreen(crt_uv, color);

	gl_FragColor = vec4(color, alpha);
	gl_FragDepth = texture2D(u_depth, clamp(crt_uv, vec2(0.0, 0.0), vec2(1.0, 1.0))).r;
}
