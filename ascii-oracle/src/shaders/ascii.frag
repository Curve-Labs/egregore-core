precision highp float;

uniform float uTime;
uniform vec2 uResolution;
uniform vec2 uGridSize;
uniform sampler2D uEnergyTexture;

// Color uniforms
uniform vec3 uColorVoid;
uniform vec3 uColorDim;
uniform vec3 uColorMid;
uniform vec3 uColorBright;
uniform vec3 uColorHighlight;
uniform vec3 uColorAccent;

varying vec2 vUv;
varying vec2 vCellUv;

// Character families:
// 0: void (space)
// 1: sparse (. · : ∙)
// 2: dots (• ◦ ○ ● ◎ ◉)
// 3: circles (◯ ⊙ ⊚ ⊛ ◐ ◑ ◒ ◓)
// 4: geometric (△ ▽ ◇ ◆ □ ■ ▢ ▣ ⬡ ⬢)
// 5: lines (│ ─ ┼ ╱ ╲ ╳ ┃ ━)
// 6: special (✦ ✧ ★ ☆ ✶ ✹ ❋ ❊)
// 7: mystic (☉ ☽ ☾ ✡ ⚝ ⚛ ⚜ ☀)

// SDF primitives
float sdCircle(vec2 p, float r) {
  return length(p) - r;
}

float sdRing(vec2 p, float r, float w) {
  return abs(length(p) - r) - w;
}

float sdBox(vec2 p, vec2 b) {
  vec2 d = abs(p) - b;
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float sdTriangle(vec2 p, float r) {
  const float k = sqrt(3.0);
  p.x = abs(p.x) - r;
  p.y = p.y + r / k;
  if (p.x + k * p.y > 0.0) p = vec2(p.x - k * p.y, -k * p.x - p.y) / 2.0;
  p.x -= clamp(p.x, -2.0 * r, 0.0);
  return -length(p) * sign(p.y);
}

float sdDiamond(vec2 p, float r) {
  p = abs(p);
  return (p.x + p.y - r) * 0.707;
}

float sdLine(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a;
  vec2 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

float sdCross(vec2 p, float r, float w) {
  p = abs(p);
  if (p.y > p.x) p = p.yx;
  return sdBox(p - vec2(r * 0.5, 0.0), vec2(r * 0.5, w)) ;
}

float sdStar(vec2 p, float r, int n, float m) {
  float an = 3.141593 / float(n);
  float en = 3.141593 / m;
  vec2 acs = vec2(cos(an), sin(an));
  vec2 ecs = vec2(cos(en), sin(en));

  float bn = mod(atan(p.x, p.y), 2.0 * an) - an;
  p = length(p) * vec2(cos(bn), abs(sin(bn)));

  p -= r * acs;
  p += ecs * clamp(-dot(p, ecs), 0.0, r * acs.y / ecs.y);

  return length(p) * sign(p.x);
}

// Draw a glyph based on energy level
float drawGlyph(vec2 localUv, float energy, float variation) {
  // Center and scale local UV
  vec2 p = (localUv - 0.5) * 2.0;

  // Select glyph based on energy
  float glyph = 1.0; // Start with empty (outside)

  if (energy < 0.1) {
    // Void - empty space
    glyph = 1.0;
  }
  else if (energy < 0.25) {
    // Sparse - small dots
    float dotSize = 0.08 + variation * 0.04;
    glyph = sdCircle(p, dotSize);
  }
  else if (energy < 0.4) {
    // Dots - medium circles
    float idx = floor(variation * 5.99);
    if (idx < 2.0) {
      glyph = sdCircle(p, 0.15 + variation * 0.1);
    } else if (idx < 4.0) {
      glyph = sdRing(p, 0.2, 0.05);
    } else {
      glyph = min(sdCircle(p, 0.25), -sdCircle(p, 0.15));
    }
  }
  else if (energy < 0.55) {
    // Circles - larger, more complex
    float idx = floor(variation * 7.99);
    if (idx < 2.0) {
      glyph = sdRing(p, 0.3, 0.05);
    } else if (idx < 4.0) {
      glyph = min(sdRing(p, 0.3, 0.04), sdCircle(p, 0.1));
    } else if (idx < 6.0) {
      // Half circles
      float circle = sdRing(p, 0.25, 0.05);
      glyph = max(circle, p.x * (idx < 5.0 ? 1.0 : -1.0));
    } else {
      glyph = min(sdRing(p, 0.3, 0.03), sdRing(p, 0.15, 0.03));
    }
  }
  else if (energy < 0.7) {
    // Geometric - triangles, diamonds, squares
    float idx = floor(variation * 9.99);
    if (idx < 3.0) {
      float flip = idx < 1.5 ? 1.0 : -1.0;
      glyph = sdTriangle(vec2(p.x, p.y * flip), 0.3);
    } else if (idx < 5.0) {
      glyph = sdDiamond(p, 0.35);
    } else if (idx < 7.0) {
      glyph = sdBox(p, vec2(0.2));
    } else {
      // Hexagon approximation
      float a = atan(p.y, p.x);
      float r = length(p);
      float hex = r - 0.25 * (1.0 + 0.1 * cos(6.0 * a));
      glyph = hex;
    }
  }
  else if (energy < 0.85) {
    // Lines - various orientations
    float idx = floor(variation * 7.99);
    float w = 0.04;
    if (idx < 2.0) {
      glyph = sdLine(p, vec2(0.0, -0.35), vec2(0.0, 0.35)) - w;
    } else if (idx < 4.0) {
      glyph = sdLine(p, vec2(-0.35, 0.0), vec2(0.35, 0.0)) - w;
    } else if (idx < 5.0) {
      glyph = sdCross(p, 0.35, w);
    } else if (idx < 6.0) {
      glyph = sdLine(p, vec2(-0.3, -0.3), vec2(0.3, 0.3)) - w;
    } else {
      // X shape
      float l1 = sdLine(p, vec2(-0.3, -0.3), vec2(0.3, 0.3)) - w;
      float l2 = sdLine(p, vec2(-0.3, 0.3), vec2(0.3, -0.3)) - w;
      glyph = min(l1, l2);
    }
  }
  else if (energy < 0.95) {
    // Special - stars
    float idx = floor(variation * 7.99);
    int points = int(4.0 + idx);
    glyph = sdStar(p, 0.3, points, 2.5);
  }
  else {
    // Mystic - complex symbols
    float idx = floor(variation * 5.99);
    if (idx < 2.0) {
      // Sun-like
      float core = sdCircle(p, 0.15);
      float rays = sdStar(p, 0.35, 8, 3.0);
      glyph = min(core, rays);
    } else if (idx < 4.0) {
      // Moon crescent
      float outer = sdCircle(p, 0.3);
      float inner = sdCircle(p - vec2(0.15, 0.0), 0.25);
      glyph = max(outer, -inner);
    } else {
      // Complex star
      float star1 = sdStar(p, 0.3, 6, 2.0);
      float star2 = sdStar(p * 1.3, 0.2, 6, 2.0);
      glyph = min(star1, star2);
    }
  }

  return glyph;
}

// Color based on energy
vec3 getColor(float energy, float glow) {
  vec3 color;

  if (energy < 0.2) {
    color = mix(uColorVoid, uColorDim, energy / 0.2);
  } else if (energy < 0.4) {
    color = mix(uColorDim, uColorMid, (energy - 0.2) / 0.2);
  } else if (energy < 0.6) {
    color = mix(uColorMid, uColorBright, (energy - 0.4) / 0.2);
  } else if (energy < 0.8) {
    color = mix(uColorBright, uColorHighlight, (energy - 0.6) / 0.2);
  } else {
    color = mix(uColorHighlight, uColorAccent, (energy - 0.8) / 0.2);
  }

  // Add glow for high energy
  if (energy > 0.7) {
    color = mix(color, uColorAccent, glow * (energy - 0.7) / 0.3);
  }

  return color;
}

void main() {
  // Get cell coordinates
  vec2 cellCoord = floor(vCellUv);
  vec2 localUv = fract(vCellUv);

  // Sample energy texture at cell center
  vec2 energyUv = (cellCoord + 0.5) / uGridSize;
  vec4 energySample = texture2D(uEnergyTexture, energyUv);
  float energy = energySample.r;

  // Variation based on position and time (for character selection within family)
  float variation = fract(sin(dot(cellCoord, vec2(12.9898, 78.233)) + uTime * 0.1) * 43758.5453);

  // Draw the glyph
  float sdf = drawGlyph(localUv, energy, variation);

  // Anti-aliased edge
  float pixelSize = 1.0 / min(uResolution.x, uResolution.y) * uGridSize.x;
  float edge = smoothstep(pixelSize, -pixelSize, sdf);

  // Glow effect for high energy characters
  float glowRadius = 0.1;
  float glow = smoothstep(glowRadius, 0.0, sdf) * 0.3;

  // Get color
  vec3 color = getColor(energy, glow);

  // Apply edge and glow
  float alpha = edge + glow * energy;

  // Fade at very low energy
  alpha *= smoothstep(0.05, 0.15, energy);

  gl_FragColor = vec4(color, alpha);
}
