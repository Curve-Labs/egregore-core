precision highp float;

uniform float uTime;
uniform vec2 uResolution;
uniform vec2 uMouse;
uniform float uMouseIntensity;

// Pulse uniforms (up to 8 pulses)
uniform vec2 uPulsePositions[8];
uniform float uPulseRadii[8];
uniform float uPulseIntensities[8];
uniform int uPulseCount;

// Oracle state
uniform float uOracleEnergy; // 0 = idle, 1 = thinking/active
uniform float uRevealProgress;

varying vec2 vUv;

#pragma glslify: snoise = require('./noise.glsl')
#pragma glslify: fbm = require('./noise.glsl')
#pragma glslify: curlNoise = require('./noise.glsl')

// Zone energy calculation
float getZoneEnergy(float radius) {
  // Core (0-0.15): high energy
  if (radius < 0.15) {
    return mix(0.9, 0.8, radius / 0.15);
  }
  // Inner (0.15-0.35): medium-high
  else if (radius < 0.35) {
    return mix(0.8, 0.6, (radius - 0.15) / 0.2);
  }
  // Middle (0.35-0.55): medium
  else if (radius < 0.55) {
    return mix(0.6, 0.4, (radius - 0.35) / 0.2);
  }
  // Outer (0.55-0.75): medium-low
  else if (radius < 0.75) {
    return mix(0.4, 0.2, (radius - 0.55) / 0.2);
  }
  // Edge (0.75-1.0): low
  else {
    return mix(0.2, 0.05, min((radius - 0.75) / 0.25, 1.0));
  }
}

// Pulse energy contribution
float getPulseEnergy(vec2 pos) {
  float energy = 0.0;

  for (int i = 0; i < 8; i++) {
    if (i >= uPulseCount) break;

    vec2 pulsePos = uPulsePositions[i];
    float pulseRadius = uPulseRadii[i];
    float pulseIntensity = uPulseIntensities[i];

    float dist = length(pos - pulsePos);
    float ringWidth = 0.05;

    // Ring-shaped pulse
    float ringDist = abs(dist - pulseRadius);
    float ring = smoothstep(ringWidth, 0.0, ringDist);

    // Inner glow
    float innerGlow = smoothstep(pulseRadius, 0.0, dist) * 0.3;

    energy += (ring + innerGlow) * pulseIntensity;
  }

  return energy;
}

// Mouse interaction energy
float getMouseEnergy(vec2 pos) {
  if (uMouseIntensity < 0.01) return 0.0;

  float dist = length(pos - uMouse);
  float radius = 0.15;

  // Soft circular influence
  float influence = smoothstep(radius, 0.0, dist);

  // Add some turbulence
  float turbulence = snoise(vec3(pos * 5.0, uTime * 2.0)) * 0.3;

  return influence * uMouseIntensity * (1.0 + turbulence);
}

void main() {
  // Convert UV to centered coordinates (-0.5 to 0.5)
  vec2 pos = vUv - 0.5;

  // Adjust for aspect ratio
  float aspect = uResolution.x / uResolution.y;
  pos.x *= aspect;

  // Distance from center (normalized)
  float radius = length(pos) * 2.0;

  // Base zone energy
  float zoneEnergy = getZoneEnergy(radius);

  // Flow field influence
  vec2 flow = curlNoise(pos, uTime * 0.05);
  float flowInfluence = snoise(vec3(pos + flow * 0.1, uTime * 0.1));

  // Multi-scale noise
  float noise1 = snoise(vec3(pos * 3.0, uTime * 0.15)) * 0.3;
  float noise2 = snoise(vec3(pos * 7.0, uTime * 0.2 + 100.0)) * 0.15;
  float noise3 = snoise(vec3(pos * 15.0, uTime * 0.3 + 200.0)) * 0.08;

  float noiseTotal = noise1 + noise2 + noise3;

  // Pulse energy
  float pulseEnergy = getPulseEnergy(pos);

  // Mouse interaction
  float mouseEnergy = getMouseEnergy(pos);

  // Oracle energy boost
  float oracleBoost = uOracleEnergy * 0.3 * (1.0 + sin(uTime * 3.0) * 0.2);

  // Combine all energy sources
  float energy = zoneEnergy
    + noiseTotal * zoneEnergy
    + flowInfluence * 0.1 * zoneEnergy
    + pulseEnergy
    + mouseEnergy
    + oracleBoost;

  // Clamp to valid range
  energy = clamp(energy, 0.0, 1.0);

  // Output energy as red channel, flow direction in green/blue
  vec2 flowDir = normalize(flow) * 0.5 + 0.5;

  gl_FragColor = vec4(energy, flowDir.x, flowDir.y, 1.0);
}
