precision highp float;

uniform sampler2D tDiffuse;
uniform vec2 uResolution;
uniform float uThreshold;
uniform float uIntensity;
uniform int uPass; // 0 = extract, 1 = blur H, 2 = blur V, 3 = composite

varying vec2 vUv;

// Gaussian blur weights
const float weights[5] = float[](0.227027, 0.1945946, 0.1216216, 0.054054, 0.016216);

vec3 extractBright(vec3 color) {
  float brightness = dot(color, vec3(0.2126, 0.7152, 0.0722));
  return color * smoothstep(uThreshold, uThreshold + 0.1, brightness);
}

vec3 blur(sampler2D tex, vec2 uv, vec2 direction) {
  vec2 texelSize = 1.0 / uResolution;
  vec3 result = texture2D(tex, uv).rgb * weights[0];

  for (int i = 1; i < 5; i++) {
    vec2 offset = direction * texelSize * float(i) * 2.0;
    result += texture2D(tex, uv + offset).rgb * weights[i];
    result += texture2D(tex, uv - offset).rgb * weights[i];
  }

  return result;
}

void main() {
  vec4 texel = texture2D(tDiffuse, vUv);

  if (uPass == 0) {
    // Extract bright areas
    gl_FragColor = vec4(extractBright(texel.rgb), texel.a);
  }
  else if (uPass == 1) {
    // Horizontal blur
    gl_FragColor = vec4(blur(tDiffuse, vUv, vec2(1.0, 0.0)), texel.a);
  }
  else if (uPass == 2) {
    // Vertical blur
    gl_FragColor = vec4(blur(tDiffuse, vUv, vec2(0.0, 1.0)), texel.a);
  }
  else {
    // Composite (additive blend)
    gl_FragColor = vec4(texel.rgb * uIntensity, texel.a);
  }
}
