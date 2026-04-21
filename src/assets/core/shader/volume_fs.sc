$input vWorldPos, vModelPos, vNormal, vModelNormal, vTangent, vBinormal, vTexCoord0, vTexCoord1, vLinearShadowCoord0, vLinearShadowCoord1, vLinearShadowCoord2, vLinearShadowCoord3, vSpotShadowCoord, vProjPos, vPrevProjPos
#include <forward_pipeline.sh>

// (enable, steps, sigma, edgeWidthMeters)
uniform vec4 uVolCyl;     // e.g. (1, 16, 8.0, 0.1)
// (rgb, intensity)
uniform vec4 uVolTint;    // e.g. (1,1,1, 1)
// Camera position in THIS mesh object space
uniform vec4 uCamObj;     // (x,y,z,unused)

// Ray / finite cylinder (axis Y), radius R, y in [ymin,ymax]
bool intersectCylY(vec3 ro, vec3 rd, float R, float ymin, float ymax, out float t0, out float t1)
{
    float a = rd.x*rd.x + rd.z*rd.z;
    float b = 2.0*(ro.x*rd.x + ro.z*rd.z);
    float c = ro.x*ro.x + ro.z*ro.z - R*R;

    float tc0 = -1e30, tc1 = +1e30;
    if (a > 1e-8) {
        float disc = b*b - 4.0*a*c;
        if (disc < 0.0) return false;
        float sdisc = sqrt(disc);
        tc0 = (-b - sdisc) / (2.0*a);
        tc1 = (-b + sdisc) / (2.0*a);
        if (tc0 > tc1) { float t = tc0; tc0 = tc1; tc1 = t; }
    } else {
        if (c > 0.0) return false;
    }

    float ty0 = -1e30, ty1 = +1e30;
    if (abs(rd.y) > 1e-8) {
        ty0 = (ymin - ro.y) / rd.y;
        ty1 = (ymax - ro.y) / rd.y;
        if (ty0 > ty1) { float t = ty0; ty0 = ty1; ty1 = t; }
    } else {
        if (ro.y < ymin || ro.y > ymax) return false;
    }

    float enter = max(tc0, ty0);
    float exit  = min(tc1, ty1);
    enter = max(enter, 0.0);
    if (exit <= enter) return false;

    t0 = enter; t1 = exit;
    return true;
}

float radialFade(vec2 xz, float R, float edgeW)
{
    float d = length(xz);
    return 1.0 - smoothstep(R - edgeW, R, d);
}

void main()
{
    if (uVolCyl.x < 0.50) { gl_FragColor = vec4(0,0,0,1); return; }

    // Ray in OBJ space: from camera (OBJ) to current fragment (OBJ)
    vec3 ro = uCamObj.xyz;
    vec3 rd = normalize(vModelPos - ro);

    // Cylinder OBJ: R=1, y in [-1, +1]
    const float R    = 1.0;
    const float yMin = -1.0;
    const float yMax =  1.0;

    float t0, t1;
    if (!intersectCylY(ro, rd, R, yMin, yMax, t0, t1)) { discard; }

    int   STEPS = int(clamp(uVolCyl.y, 4.0, 64.0));
    float sigma = uVolCyl.z;
    float edgeW = max(uVolCyl.w, 1e-4);

    float segLen = t1 - t0;
    float ds     = segLen / float(STEPS);

    // Small jitter to reduce banding
    float h = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898,78.233))) * 43758.5453);
    float t = t0 + h * ds;

    float acc = 0.0;
    const float EARLY = 0.98;

    for (int i = 0; i < 64; ++i) {
        if (i >= STEPS) break;

        vec3 p = ro + rd * t;                 // OBJ point
        float dens = radialFade(p.xz, R, edgeW);
        acc += dens * ds;

        float aTmp = 1.0 - exp(-sigma * acc);
        if (aTmp > EARLY) { acc = -log(1.0 - EARLY) / max(sigma,1e-6); break; }

        t += ds;
    }

    float alpha = clamp(1.0 - exp(-sigma * acc), 0.0, 1.0) * uVolTint.a;
    vec3  color = uVolTint.rgb * alpha;  // premultiplied
    gl_FragColor = vec4(color, alpha);
}
