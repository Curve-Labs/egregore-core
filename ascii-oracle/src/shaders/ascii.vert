precision highp float;

attribute vec3 position;
attribute vec2 uv;

uniform mat4 modelViewMatrix;
uniform mat4 projectionMatrix;

varying vec2 vUv;
varying vec2 vCellUv;

uniform vec2 uGridSize; // Number of cols/rows
uniform vec2 uCellSize; // Size of each cell in UV space

void main() {
  vUv = uv;

  // Calculate which cell this vertex belongs to
  vCellUv = uv * uGridSize;

  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}
