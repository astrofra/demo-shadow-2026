$input v_texcoord0

// HARFANG(R) Copyright (C) 2022 Emmanuel Julien, NWNC HARFANG. Released under GPL/LGPL/Commercial Licence, see licence.txt for details.
#include <forward_pipeline.sh>

SAMPLER2D(u_color, 0);
SAMPLER2D(u_depth, 1);
uniform vec4 uCompositingParams[4]; // [0].x: vignette start, [0].y: vignette end, [0].z: vignette strength, [0].w: circular blur strength
								  // [1].x: crt curvature, [1].y: crt mask density, [1].z: crt mask intensity, [1].w: left light shift

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

vec3 SampleCompositedColor(vec2 uv) {
	vec2 safe_uv = clamp(uv, vec2(0.0, 0.0), vec2(1.0, 1.0));
	float exposure = uAAAParams[1].x;
	vec3 color = texture2D(u_color, safe_uv).xyz;
	color = SimpleReinhardToneMapping(color, exposure);
	return color;
}

float ComputePerceivedLuma(vec3 color) {
	return dot(color, vec3(0.2126, 0.7152, 0.0722));
}

vec2 WarpCRTUV(vec2 uv) {
	float curvature = max(uCompositingParams[1].x, 0.0) * 0.18;
	vec2 screen_pos = uv * 2.0 - vec2(1.0, 1.0);
	float radius_sq = dot(screen_pos, screen_pos);

	vec2 warped = screen_pos;
	warped.x *= 1.0 + curvature * (radius_sq * 0.18 + screen_pos.y * screen_pos.y * 0.10);
	warped.y *= 1.0 + curvature * (radius_sq * 0.22 + screen_pos.x * screen_pos.x * 0.12);

	return warped * 0.5 + vec2(0.5, 0.5);
}

vec2 ApplyLeftLightShift(vec2 uv) {
	float shift_strength = max(uCompositingParams[1].w, 0.0) * 0.15;

	if (shift_strength <= 0.0) {
		return uv;
	}

	vec2 pixel_uv = vec2(1.0 / uResolution.x, 0.0);
	float left_luma = 0.0;
	left_luma += ComputePerceivedLuma(SampleCompositedColor(uv - pixel_uv * 1.0));
	left_luma += ComputePerceivedLuma(SampleCompositedColor(uv - pixel_uv * 2.0));
	left_luma += ComputePerceivedLuma(SampleCompositedColor(uv - pixel_uv * 3.0));
	left_luma += ComputePerceivedLuma(SampleCompositedColor(uv - pixel_uv * 4.0));
	left_luma *= 0.25;

	float displacement_pixels = left_luma * shift_strength;
	vec2 shifted_uv = uv - pixel_uv * displacement_pixels;
	return clamp(shifted_uv, vec2(0.0, 0.0), vec2(1.0, 1.0));
}

float SampleSceneDepth(vec2 uv) {
	return texture2D(u_depth, clamp(uv, vec2(0.0, 0.0), vec2(1.0, 1.0))).r;
}

float ComputeDepthEdge(vec2 uv) {
	vec2 texel = 1.0 / uResolution.xy;
	float center = SampleSceneDepth(uv);
	float edge = 0.0;
	edge += abs(center - SampleSceneDepth(uv + vec2(texel.x, 0.0)));
	edge += abs(center - SampleSceneDepth(uv - vec2(texel.x, 0.0)));
	edge += abs(center - SampleSceneDepth(uv + vec2(0.0, texel.y)));
	edge += abs(center - SampleSceneDepth(uv - vec2(0.0, texel.y)));
	return clamp(edge * 120.0, 0.0, 1.0);
}

float ComputeLumaEdge(vec2 uv, vec3 center_color) {
	vec2 texel = 1.0 / uResolution.xy;
	float center = ComputePerceivedLuma(center_color);
	float edge = 0.0;
	edge += abs(center - ComputePerceivedLuma(SampleCompositedColor(uv + vec2(texel.x, 0.0))));
	edge += abs(center - ComputePerceivedLuma(SampleCompositedColor(uv - vec2(texel.x, 0.0))));
	edge += abs(center - ComputePerceivedLuma(SampleCompositedColor(uv + vec2(0.0, texel.y))));
	edge += abs(center - ComputePerceivedLuma(SampleCompositedColor(uv - vec2(0.0, texel.y))));
	return clamp(edge * 2.8, 0.0, 1.0);
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
	float edge_ink_strength = clamp(lens_mask * max(uCompositingParams[0].w, 0.0) * 0.03, 0.0, 1.0);
	return mix(base_color, vec3(0.01, 0.008, 0.006), edge_ink_strength);
}

vec3 ApplyPrintTexture(vec2 uv, vec3 color) {
	float density = max(uCompositingParams[1].y, 0.0);
	float intensity = clamp(uCompositingParams[1].z, 0.0, 1.0);

	if (density <= 0.0 || intensity <= 0.0) {
		return color;
	}

	vec2 grid = uv * uResolution.xy * (0.18 + density * 0.12);
	float weave = 0.5 + 0.5 * cos((grid.x * 0.85 + grid.y * 0.22) * PI * 2.0);
	float grain = 0.5 + 0.5 * cos((grid.y * 0.93 - grid.x * 0.17) * PI * 2.0);
	float print_mask = 0.96 + (weave * 0.025 + grain * 0.015 - 0.02) * intensity;
	return color * print_mask;
}

vec3 ApplyMignolaBanding(vec3 color) {
	float luma = max(ComputePerceivedLuma(color), 1e-4);
	float banded_luma = floor(pow(clamp(luma, 0.0, 1.0), 0.90) * 3.0 + 0.5) / 3.0;
	vec3 banded_color = color * (banded_luma / luma);
	float shadow_crush = mix(0.16, 1.0, smoothstep(0.05, 0.36, luma));
	float midtone_mask = smoothstep(0.04, 0.78, luma) * (1.0 - smoothstep(0.78, 1.0, luma));
	color *= shadow_crush;
	color = mix(color, banded_color, 0.48 * midtone_mask);
	return max(color, vec3_splat(0.0));
}

vec3 ApplyInkContours(vec2 uv, vec3 color) {
	float luma = ComputePerceivedLuma(color);
	float depth_edge = ComputeDepthEdge(uv);
	float luma_edge = ComputeLumaEdge(uv, color);
	float contour_boost = 1.0 + max(uCompositingParams[0].w, 0.0) * 0.02;
	float shadow_bias = 1.0 - smoothstep(0.55, 1.0, luma);
	float edge = clamp((depth_edge * 0.85 + luma_edge * 0.65) * contour_boost, 0.0, 1.0);
	edge *= mix(0.65, 1.0, shadow_bias);
	return mix(color, vec3(0.01, 0.008, 0.006), edge * 0.88);
}

void main() {
#if 1
	vec2 screen_uv = WarpCRTUV(v_texcoord0);
	screen_uv = ApplyLeftLightShift(screen_uv);
	vec4 in_sample = Sharpen(screen_uv, uAAAParams[2].y);

	vec3 color = ApplyMignolaBanding(in_sample.xyz);
	color = ApplyInkContours(screen_uv, color);
	float lens_mask = ComputeLensEdgeMask(screen_uv);
	if (lens_mask > 0.001) {
		color = ApplyLensEdgeDefect(screen_uv, color, lens_mask);
	}
	color = ApplyLensVignette(color, lens_mask);
	float alpha = in_sample.w;
#else
	vec2 screen_uv = WarpCRTUV(v_texcoord0);
	vec4 in_sample = texture2D(u_color, screen_uv);

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
	color = ApplyPrintTexture(screen_uv, color);

	gl_FragColor = vec4(color, alpha);
	gl_FragDepth = texture2D(u_depth, clamp(screen_uv, vec2(0.0, 0.0), vec2(1.0, 1.0))).r;
}
