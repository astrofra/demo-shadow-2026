$input vWorldPos, vModelPos, vNormal, vModelNormal, vTangent, vBinormal, vTexCoord0, vTexCoord1, vLinearShadowCoord0, vLinearShadowCoord1, vLinearShadowCoord2, vLinearShadowCoord3, vSpotShadowCoord, vProjPos, vPrevProjPos

#include <forward_pipeline.sh>

// Surface attributes
uniform vec4 uDiffuseColor;
uniform vec4 uSpecularColor;
uniform vec4 uSelfColor;
uniform vec4 uMatAttribute;

// Entry point of the forward pipeline default uber shader (Phong and PBR)
void main() {

	vec3 view = mul(u_view, vec4(vWorldPos, 1.0)).xyz;
	vec3 P = vWorldPos; 
	vec3 V = normalize(GetT(u_invView) - P);
	vec3 N = normalize(vNormal);
	float NdotV = clamp(dot(N, V), 0.0, 1.0);
	float fake_fresnel = pow(NdotV, 2.0);

	vec4 frag = vec4(fake_fresnel, 0.0, 0.0, 1.0);
	gl_FragColor = frag;
}
