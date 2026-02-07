import * as THREE from 'three'

// SVG structure:
// - cls-1 "Digital Souls" at y=276 (BOTTOM) - full white, full opacity → should be ASCII FILLED
// - cls-2 "We Build" at y=7 (TOP) - white with 50% opacity → should be KNOCKOUT (black)

// Create texture with dual channels:
// - Red channel: where ASCII cloud should be dense ("Digital Souls")
// - Green channel: where knockout/black should appear ("We Build")
export function createDualLayerTexture(
  width: number,
  height: number,
  marginX: number = 0.1,
  marginY: number = 0.15
): Promise<THREE.CanvasTexture> {
  return new Promise((resolve) => {
    const canvas = document.createElement('canvas')
    canvas.width = width
    canvas.height = height
    const ctx = canvas.getContext('2d')!

    // Clear with black
    ctx.fillStyle = 'black'
    ctx.fillRect(0, 0, width, height)

    // Calculate content area with margins
    const contentX = width * marginX
    const contentY = height * marginY
    const contentW = width * (1 - 2 * marginX)
    const contentH = height * (1 - 2 * marginY)

    // Load SVG
    const img = new Image()
    const blob = new Blob([DIGITAL_SOULS_SVG], { type: 'image/svg+xml' })
    const url = URL.createObjectURL(blob)

    img.onload = () => {
      // Draw SVG centered in content area
      const svgAspect = 1303.4 / 537.02
      const contentAspect = contentW / contentH

      let drawW, drawH, offsetX, offsetY

      if (svgAspect > contentAspect) {
        drawW = contentW
        drawH = contentW / svgAspect
        offsetX = contentX
        offsetY = contentY + (contentH - drawH) / 2
      } else {
        drawH = contentH
        drawW = contentH * svgAspect
        offsetX = contentX + (contentW - drawW) / 2
        offsetY = contentY
      }

      ctx.drawImage(img, offsetX, offsetY, drawW, drawH)
      URL.revokeObjectURL(url)

      // Process pixels to create dual-channel texture
      // The SVG has two text layers with different brightness:
      // - "Digital Souls" (cls-1): fill #fff, full opacity → renders as ~255 brightness
      // - "We Build" (cls-2): fill #f2f2f2, opacity 0.5 → renders as ~120 brightness on black bg

      const imageData = ctx.getImageData(0, 0, width, height)
      const data = imageData.data

      // Use brightness to distinguish the two layers
      const DIGITAL_SOULS_THRESHOLD = 180  // Bright pixels = Digital Souls
      const WE_BUILD_MIN = 30              // Dim pixels = We Build (50% opacity text)
      const WE_BUILD_MAX = 180             // Upper bound for We Build

      for (let y = 0; y < height; y++) {
        for (let x = 0; x < width; x++) {
          const i = (y * width + x) * 4
          const r = data[i]
          const g = data[i + 1]
          const b = data[i + 2]
          const brightness = (r + g + b) / 3

          if (brightness >= DIGITAL_SOULS_THRESHOLD) {
            // Bright pixels = "Digital Souls" → red channel (boost/fill)
            data[i] = 255         // R: boost marker
            data[i + 1] = 0       // G
            data[i + 2] = 0       // B
          } else if (brightness >= WE_BUILD_MIN && brightness < WE_BUILD_MAX) {
            // Dim pixels = "We Build" → green channel (knockout)
            data[i] = 0           // R
            data[i + 1] = 255     // G: knockout marker
            data[i + 2] = 0       // B
          } else {
            // Black/empty - no effect
            data[i] = 0
            data[i + 1] = 0
            data[i + 2] = 0
          }
          data[i + 3] = 255 // Full alpha
        }
      }

      ctx.putImageData(imageData, 0, 0)

      // Create texture - flipY=true (default) gives us correct mapping:
      // - Canvas top (We Build) → UV y=1 → Screen top
      // - Canvas bottom (Digital Souls) → UV y=0 → Screen bottom
      const texture = new THREE.CanvasTexture(canvas)
      // flipY defaults to true, which is what we want
      texture.minFilter = THREE.LinearFilter
      texture.magFilter = THREE.LinearFilter
      texture.needsUpdate = true

      resolve(texture)
    }

    img.src = url
  })
}

// The SVG content
export const DIGITAL_SOULS_SVG = `<?xml version="1.0" encoding="UTF-8"?>
<svg id="Layer_2" data-name="Layer 2" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1303.4 537.02">
  <defs>
    <style>
      .cls-1 {
        fill: #fff;
        font-size: 12.4px;
      }
      .cls-1, .cls-2 {
        font-family: AndaleMono, 'Andale Mono', monospace;
      }
      .cls-2 {
        fill: #f2f2f2;
        font-size: 8px;
        opacity: .5;
      }
    </style>
  </defs>
  <g id="Layer_2-2" data-name="Layer 2">
    <text class="cls-1" transform="translate(0 276.03) scale(.84 1)"><tspan x="0" y="0" xml:space="preserve">                                   0                            0           00                                                      0                                                                           </tspan><tspan x="0" y="10.33" xml:space="preserve">  00000000       00000            0000                        0000    000  00                       00   00                       0000000                                               00   00                 </tspan><tspan x="0" y="20.66" xml:space="preserve">  000000000000000000000000      0000000                     00000000  0000000                    000000000                      0000000000000000                                     000000000                  </tspan><tspan x="0" y="30.99" xml:space="preserve">   000000000000000000000000000   000000                      000000   000000                      00000000                    0000000000000000                            00          0000000                   </tspan><tspan x="0" y="41.33" xml:space="preserve">   00        000000 0000000000    0000                         000    000000                       000000                 000000000    0000                            0000            000000                   </tspan><tspan x="0" y="51.66" xml:space="preserve">    00     00000000    0000000                     0                00000000000000      0          000000               00000000000                       0           0000          00 000000            0      </tspan><tspan x="0" y="61.99" xml:space="preserve">         0000000000     000000   000             00000000    0000  0000000000000     000000000     000000             0000000000000                    0000000      000000    0000000  000000         0000000000</tspan><tspan x="0" y="72.32" xml:space="preserve">       000000000000     000000 00000000      00000000000000 00000000  00000000   0000000000000000  000000           000000000000000                00000000000000   00000     000000   000000     000000000000  </tspan><tspan x="0" y="82.65" xml:space="preserve">     00000000000000    0000000  0000000  0000000  00000000  0000000   000000   000000   000000000  000000           000000000000000000          0000000  00000000   00000     000000   000000   000000  00000   </tspan><tspan x="0" y="92.98" xml:space="preserve">     00000000000000     000000  0000000  0000000    000000   000000   000000   000000     000000   000000          00 000000000000000000000000  0000000    000000  000000     000000   000000   000000    00    </tspan><tspan x="0" y="103.31" xml:space="preserve">   0000000000000000     000000   000000  0000000    000000   000000   000000   000000     000000   000000          0      0000000      0000000  0000000    000000  000000     000000   000000   000000    00    </tspan><tspan x="0" y="113.64" xml:space="preserve">  0    000000000000     000000   000000  0000000    000000   000000   000000   000000     000000   000000                  00000        000000  0000000    000000  000000     000000   000000   000000   000000 </tspan><tspan x="0" y="123.98" xml:space="preserve">   0    00000000000     000000   000000  0000000    000000   000000   000000   000000     000000   000000                    000      00000000  0000000    000000  000000     000000   000000   0000000000000000</tspan><tspan x="0" y="134.31" xml:space="preserve">         0000000000     000000   000000  0000000    000000   000000   000000   000000     000000   000000                    00         000000  0000000    000000  000000     000000   000000   000000000000000 </tspan><tspan x="0" y="144.64" xml:space="preserve">         0000000000     000000   000000  0000000    000000   000000   000000   000000     000000   000000                               000000  0000000    000000  000000     000000   000000      0000   00000 </tspan><tspan x="0" y="154.97" xml:space="preserve">         000 000000     000000   000000  0000000    000000   000000   000000   000000     000000   000000                               000000  0000000    000000  000000     000000   000000             00000 </tspan><tspan x="0" y="165.3" xml:space="preserve">        000  000000     000000   000000  0000000    000000   000000   000000   000000     000000   000000                   00          000000  0000000    000000  000000     000000   000000             00000 </tspan><tspan x="0" y="175.63" xml:space="preserve">       000000000000     000000   000000  000000000  000000   000000   000000   000000     000000   000000                00000000       00000   0000000    000000  000000     000000   000000000000000    000000</tspan><tspan x="0" y="185.96" xml:space="preserve">    000000000000000     000000   000000   0000000000000000   000000   000000   0000000   0000000   000000              00000000000000  0000     0000000    000000  0000000   0000000   00000000000000000  000000</tspan><tspan x="0" y="196.29" xml:space="preserve">  000000000000000000000000      00000000     0000000000000   0000000000000000000000000000000000000000000000         00000000000000000000        000000000000000   00000000000000000000000000000   00000000000   </tspan><tspan x="0" y="206.62" xml:space="preserve">0000         00000000000         000000        000  0000000  0000000   0000000  00000000  0000000  0000000         0000        0000000            0000000000        00000000   000000  0000000      000000      </tspan><tspan x="0" y="216.96" xml:space="preserve">000              0000               00       00     0000000     00        00        00       00       00          000             00                  000              000       00       00         00         </tspan><tspan x="0" y="227.29" xml:space="preserve">00                                         0000000  00000000                                                      00                                                                                            </tspan><tspan x="0" y="237.62" xml:space="preserve">00                                       000000000000000                                                          00                                                                                            </tspan><tspan x="0" y="247.95" xml:space="preserve">00                                      00   00000000                                                              00                                                                                           </tspan><tspan x="0" y="258.28" xml:space="preserve">  00                                    0       000                                                                  00                                                                                         </tspan></text>
    <text class="cls-2" transform="translate(277.24 6.76)"><tspan x="0" y="0" xml:space="preserve">                                                                                                                                                            </tspan><tspan x="0" y="9.6" xml:space="preserve">                                                                                                                                                            </tspan><tspan x="0" y="19.2" xml:space="preserve">                                                                                                                                                            </tspan><tspan x="0" y="28.8" xml:space="preserve">                                                                                                                                                            </tspan><tspan x="0" y="38.4" xml:space="preserve">                                                                                                                                                            </tspan><tspan x="0" y="48" xml:space="preserve">                                                                                                                                                            </tspan><tspan x="0" y="57.6" xml:space="preserve">                                                                                                                                                            </tspan><tspan x="0" y="67.2" xml:space="preserve">                                                                                                                                                            </tspan><tspan x="0" y="76.8" xml:space="preserve">                                                                                                                                                            </tspan><tspan x="0" y="86.4" xml:space="preserve">                      00000                00                                   0000000                                  00             00                  </tspan><tspan x="0" y="96" xml:space="preserve">                    00000000000          00000                              00000    000                               0000            000                  </tspan><tspan x="0" y="105.6" xml:space="preserve">                  00      000          000000000                    0    0000000     00000                      0000  00000          00000                  </tspan><tspan x="0" y="115.2" xml:space="preserve">                 000     00                00000                     0000000          000000                   00000   0000            000                  </tspan><tspan x="0" y="124.8" xml:space="preserve">                 0000            0         00000       0000                 00      0000           0        0          0000         000000                  </tspan><tspan x="0" y="134.4" xml:space="preserve">                 000           000         00000     00   000              000   00000000000     000     0000   0000   0000       00   000                  </tspan><tspan x="0" y="144" xml:space="preserve">                   000        000000       000     0000   000              000  000    0000000  0000      000  00000   0000     000    000                  </tspan><tspan x="0" y="153.6" xml:space="preserve">                   00000       00000       000   000000   00               000  0       00000    000      000    000   0000    00      000                  </tspan><tspan x="0" y="163.2" xml:space="preserve">                     00000   0000000     000      000  000                 000            000    000      000   0000   0000   000      000                  </tspan><tspan x="0" y="172.8" xml:space="preserve">                    00000  0000  00000  000      0000                    000              0000   000      000   0000   0000   0000     000                  </tspan><tspan x="0" y="182.4" xml:space="preserve">                      0000000     000  000        000                  000000000          00     000      000   0000   0000   000      000                  </tspan><tspan x="0" y="192" xml:space="preserve">                        00000       00000          0000   00         00000000000000     00       000    0000000 000000 000000   000    000  00              </tspan><tspan x="0" y="201.6" xml:space="preserve">                        000         000            0000000           00      00000000000           00000  000   0000   0000      000000  00000              </tspan><tspan x="0" y="211.2" xml:space="preserve">                          0         0                000            0           0000000             00    0     00     00         000     00                </tspan><tspan x="0" y="220.8" xml:space="preserve">                                                                                                                                                            </tspan><tspan x="0" y="230.4" xml:space="preserve">                                                                                                                                                            </tspan><tspan x="0" y="240" xml:space="preserve">                                                                                                                                                            </tspan><tspan x="0" y="249.6" xml:space="preserve">                                                                                                                                                            </tspan></text>
  </g>
</svg>`
