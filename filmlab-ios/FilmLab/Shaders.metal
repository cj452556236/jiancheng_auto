#include <metal_stdlib>
using namespace metal;

// Film engine: bright pass -> separable blur (halation and bloom) -> film, enlarger and paper.
// Values stay in display (gamma) encoding like the web version; linear light is used where
// light physically adds up (exposure, halation, print exposure).

struct VOut {
    float4 position [[position]];
    float2 uv;
};

vertex VOut fullscreenVertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2u), float(vid & 2u));
    VOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);

struct BrightUniforms {
    float4 crop;
    float4 params;   // texel x, texel y, threshold, unused
};

struct BlurUniforms {
    float4 dir;
};

struct FilmUniforms {
    float4 crop;
    float4 res;
    float4 filmA;
    float4 filmB;
    float4 wb;
    float4 slope;
    float4 offset;
    float4 power;
    float4 hsl[6];
    float4 shadowTint;
    float4 highTint;
    float4 bwMix;
    float4 halColor;
    float4 printGain;
    float4 printParams;
    float4 paperBlack;
    float4 paperWhite;
    float4 toneS;
    float4 toneM;
    float4 toneH;
    float4 fx;
    float4 fx2;
    float4 fx3;
};

static float3 toLinear(float3 c) {
    return pow(max(c, float3(0.0)), float3(2.2));
}

fragment float4 brightFragment(VOut in [[stage_in]],
                               texture2d<float> src [[texture(0)]],
                               constant BrightUniforms& U [[buffer(0)]]) {
    float2 uv = U.crop.xy + in.uv * U.crop.zw;
    float2 t = U.params.xy;
    float3 c = toLinear(src.sample(linearSampler, uv + float2(-t.x, -t.y)).rgb)
             + toLinear(src.sample(linearSampler, uv + float2(t.x, -t.y)).rgb)
             + toLinear(src.sample(linearSampler, uv + float2(-t.x, t.y)).rgb)
             + toLinear(src.sample(linearSampler, uv + t).rgb);
    c *= 0.25;
    float l = max(c.r, max(c.g, c.b));
    float k = smoothstep(U.params.z, min(U.params.z + 0.3, 1.0), l);
    return float4(c * k, 1.0);
}

fragment float4 blurFragment(VOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]],
                             constant BlurUniforms& U [[buffer(0)]]) {
    float2 d = U.dir.xy;
    float3 s = tex.sample(linearSampler, in.uv).rgb * 0.2270270270;
    s += tex.sample(linearSampler, in.uv + d * 1.3846153846).rgb * 0.3162162162;
    s += tex.sample(linearSampler, in.uv - d * 1.3846153846).rgb * 0.3162162162;
    s += tex.sample(linearSampler, in.uv + d * 3.2307692308).rgb * 0.0702702703;
    s += tex.sample(linearSampler, in.uv - d * 3.2307692308).rgb * 0.0702702703;
    return float4(s, 1.0);
}

static float luma(float3 c) {
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

static float3 sCurve(float3 x, float k, float p) {
    x = clamp(x, float3(0.00001), float3(0.99999));
    float e = 1.0 + k;
    float3 lo = p * pow(x / p, float3(e));
    float3 hi = 1.0 - (1.0 - p) * pow(max((1.0 - x) / (1.0 - p), float3(0.00001)), float3(e));
    return mix(lo, hi, step(float3(p), x));
}

static float3 rgb2hsv(float3 c) {
    float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    float4 p = mix(float4(c.bg, K.wz), float4(c.gb, K.xy), float4(step(c.b, c.g)));
    float4 q = mix(float4(p.xyw, c.r), float4(c.r, p.yzx), float4(step(p.x, c.r)));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

static float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, saturate(p - K.xxx), float3(c.y));
}

static float3 hueBands(float3 c, constant FilmUniforms& U) {
    float3 hsv = rgb2hsv(saturate(c));
    float h = hsv.x * 6.0;
    float dh = 0.0;
    float ds = 0.0;
    float dv = 0.0;
    for (int i = 0; i < 6; i++) {
        float d = abs(h - float(i));
        d = min(d, 6.0 - d);
        float w = max(0.0, 1.0 - d);
        dh += w * U.hsl[i].x;
        ds += w * U.hsl[i].y;
        dv += w * U.hsl[i].z;
    }
    float sw = smoothstep(0.02, 0.3, hsv.y);
    float dss = ds * sw;
    hsv.x = fract(hsv.x + dh * sw);
    hsv.y = dss > 0.0 ? clamp(hsv.y + dss * hsv.y * (1.0 - hsv.y) * 2.0, 0.0, 1.0) : hsv.y * (1.0 + dss);
    hsv.z = clamp(hsv.z * (1.0 + dv * sw), 0.0, 1.0);
    return hsv2rgb(hsv);
}

static float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    float a = hash12(i);
    float b = hash12(i + float2(1.0, 0.0));
    float c = hash12(i + float2(0.0, 1.0));
    float d = hash12(i + float2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

static float grainAt(float2 p) {
    return (valueNoise(p) + 0.6 * valueNoise(p * 1.93 + 7.3) + 0.35 * valueNoise(p * 3.71 + 2.1)) / 1.95;
}

fragment float4 finalFragment(VOut in [[stage_in]],
                              texture2d<float> src [[texture(0)]],
                              texture2d<float> halTex [[texture(1)]],
                              texture2d<float> bloomTex [[texture(2)]],
                              texture2d<float> leakTex [[texture(3)]],
                              texture2d<float> dustTex [[texture(4)]],
                              constant FilmUniforms& U [[buffer(0)]]) {
    float2 uv = U.crop.xy + in.uv * U.crop.zw;
    float3 srcColor = src.sample(linearSampler, uv).rgb;
    if (U.res.w > 0.5) {
        return float4(srcColor, 1.0);
    }

    // Scene light reaches the emulsion.
    float3 lin0 = toLinear(srcColor);
    float3 lin = lin0 * exp2(U.filmA.x);
    float3 hal = halTex.sample(linearSampler, in.uv).rgb;
    float3 blm = bloomTex.sample(linearSampler, in.uv).rgb;
    float lb = max(lin0.r, max(lin0.g, lin0.b));
    float halo = max(max(hal.r, max(hal.g, hal.b)) - lb * smoothstep(U.fx3.z, min(U.fx3.z + 0.3, 1.0), lb), 0.0);
    lin += U.halColor.rgb * halo * U.filmB.w * 2.4;
    lin += blm * U.fx3.x * 0.9;
    lin = mix(lin, lin * 0.9 + 0.015, float3(U.fx3.x * 0.6));
    lin *= U.wb.rgb;
    if (U.fx3.y > 0.5) {
        float ir = max(lin.g * 1.15 - lin.b * 0.3, lin.r * 1.02);
        lin = float3(ir, lin.r, lin.g);
    }
    lin = max(lin, float3(0.0));

    // Dye response of the film.
    float3 c = pow(lin, float3(1.0 / 2.2));
    c = pow(max(c * U.slope.rgb + U.offset.rgb, float3(0.0)), U.power.rgb);
    if (U.filmB.z > 0.5) {
        c = float3(dot(c, U.bwMix.rgb));
    }
    c = sCurve(c, U.filmA.y, U.filmA.z);
    if (U.filmB.z < 0.5) {
        c = hueBands(c, U);
        float y0 = luma(c);
        float mx0 = max(c.r, max(c.g, c.b));
        float mn0 = min(c.r, min(c.g, c.b));
        float s0 = (mx0 - mn0) / max(mx0, 0.0001);
        float sat = U.filmA.w > 1.0 ? 1.0 + (U.filmA.w - 1.0) * (1.0 - s0 * s0) : U.filmA.w;
        c = mix(float3(y0), c, float3(sat));
        float mx1 = max(c.r, max(c.g, c.b));
        float mn1 = min(c.r, min(c.g, c.b));
        if (mx1 > 1.0) c = mix(float3(y0), c, float3((1.0 - y0) / max(mx1 - y0, 0.0001)));
        if (mn1 < 0.0) c = mix(float3(y0), c, float3(y0 / max(y0 - mn1, 0.0001)));
    }
    float y1 = luma(c);
    c += U.shadowTint.rgb * (1.0 - smoothstep(0.0, 0.6, y1)) + U.highTint.rgb * smoothstep(0.4, 1.0, y1);
    c = mix(float3(U.filmB.x), float3(U.filmB.y), saturate(c));

    // Enlarger and paper.
    float stops = 0.0;
    if (U.printParams.z > 0.5) {
        stops = (floor(clamp(in.uv.x, 0.0, 0.9999) * 5.0) - 2.0) * 0.5 * U.printParams.w;
    }
    float2 q = in.uv - 0.5;
    float vig = smoothstep(0.25, 1.15, length(q * 2.0) * 0.7071);
    float3 pl = toLinear(c) * U.printGain.rgb * exp2(-stops) * (1.0 - U.fx2.x * vig * 0.85);
    c = pow(max(pl, float3(0.0)), float3(1.0 / 2.2));
    c = sCurve(c, U.printParams.x, 0.5);
    if (U.fx.w > 0.0) {
        float t = luma(c);
        float3 g = mix(mix(U.toneS.rgb, U.toneM.rgb, float3(saturate(t * 2.0))), U.toneH.rgb, float3(saturate(t * 2.0 - 1.0)));
        c = mix(c, g, float3(U.fx.w));
    }
    c = mix(U.paperBlack.rgb, U.paperWhite.rgb, c);

    // Light leak, dust and grain.
    float3 lk = leakTex.sample(linearSampler, in.uv).rgb * U.fx2.y;
    c = 1.0 - (1.0 - c) * (1.0 - lk);
    float dust = dustTex.sample(linearSampler, in.uv).r * U.fx2.z;
    c = mix(c, mix(U.paperWhite.rgb, float3(0.03), float3(U.fx2.w)), float3(dust));
    float2 px = in.uv * U.res.xy;
    float cellTrue = U.fx.y * max(U.res.x, U.res.y) / 2400.0;
    float cell = max(cellTrue, 0.75);
    float att = clamp(cellTrue * 1.1, 0.35, 1.0);
    float2 gp = px / cell + U.res.z;
    float3 gn = float3(grainAt(gp) - 0.5);
    if (U.filmB.z < 0.5) {
        gn += U.fx.z * att * (float3(grainAt(gp + 13.7), grainAt(gp + 41.3), grainAt(gp + 77.9)) - 0.5);
    }
    float y2 = luma(c);
    c += gn * U.fx.x * att * (0.1 + 3.6 * y2 * (1.0 - y2)) * 0.45;
    c += (hash12(px * 0.73 + 3.1) - 0.5) * U.printParams.y;
    return float4(saturate(c), 1.0);
}
