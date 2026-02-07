precision highp float;

uniform sampler2D tDiffuse;
uniform sampler2D tBloom;
uniform vec2 uResolution;
uniform float uTime;

// Post-processing controls
uniform float uBloomIntensity;
uniform float uChromaticAberration;
uniform float uVignetteIntensity;
uniform float uVignetteRadius;
uniform float uScanlineIntensity;
uniform float uNoiseIntensity;

varying vec2 vUv;

// Simple hash for noise
float hash(vec2 p) {
  return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

// Film grain noise
float filmGrain(vec2 uv, float time) {
  vec2 p = uv * uResolution;
  return hash(p + time * 100.0) * 2.0 - 1.0;
}

// Chromatic aberration
vec3 chromaticAberration(sampler2D tex, vec2 uv, float amount) {
  vec2 center = uv - 0.5;
  float dist = length(center);
  vec2 offset = center * dist * amount;

  float r = texture2D(tex, uv + offset).r;
  float g = texture2D(tex, uv).g;
  float b = texture2D(tex, uv - offset).b;

  return vec3(r, g, b);
}

// Vignette
float vignette(vec2 uv, float radius, float softness) {
  vec2 center = uv - 0.5;
  float dist = length(center);
  return 1.0 - smoothstep(radius - softness, radius + softness, dist);
}

// Scanlines
float scanlines(vec2 uv, float intensity) {
  float line = sin(uv.y * uResolution.y * 3.14159) * 0.5 + 0.5;
  return 1.0 - intensity * (1.0 - line);
}

void main() {
  vec2 uv = vUv;

  // Base color with chromatic aberration
  vec3 color;
  if (uChromaticAberration > 0.001) {
    color = chromaticAberration(tDiffuse, uv, uChromaticAberration);
  } else {
    color = texture2D(tDiffuse, uv).rgb;
  }

  // Add bloom
  vec3 bloom = texture2D(tBloom, uv).rgb;
  color += bloom * uBloomIntensity;

  // Apply vignette
  float vig = vignette(uv, uVignetteRadius, 0.3);
  color *= mix(1.0, vig, uVignetteIntensity);

  // Apply scanlines
  if (uScanlineIntensity > 0.001) {
    color *= scanlines(uv, uScanlineIntensity);
  }

  // Apply film grain
  if (uNoiseIntensity > 0.001) {
    float noise = filmGrain(uv, uTime);
    color += noise * uNoiseIntensity * 0.1;
  }

  // Clamp to valid range
  color = clamp(color, 0.0, 1.0);

  gl_FragColor = vec4(color, 1.0);
}
