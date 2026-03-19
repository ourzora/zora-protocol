export type RGB = [r: number, g: number, b: number];

/** Check if the terminal supports 24-bit truecolor. */
export function supportsTruecolor(): boolean {
  if (!process.stdout.isTTY) return false;
  const ct = process.env.COLORTERM;
  if (ct === "truecolor" || ct === "24bit") return true;
  if (typeof process.stdout.getColorDepth === "function") {
    return process.stdout.getColorDepth() >= 24;
  }
  return false;
}

// -- color helpers --

function hexToRgb(hex: string): RGB {
  const n = parseInt(hex.replace("#", ""), 16);
  return [(n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff];
}

function lerp(a: number, b: number, t: number): number {
  return a + (b - a) * t;
}

function clamp(v: number, min: number, max: number): number {
  return v < min ? min : v > max ? max : v;
}

// -- compositing --

/** Alpha-over: composite `fg` with alpha `a` onto `bg`. */
function alphaOver(bg: RGB, fg: RGB, a: number): RGB {
  return [lerp(bg[0], fg[0], a), lerp(bg[1], fg[1], a), lerp(bg[2], fg[2], a)];
}

// -- gaussian blur approximation --

/** Gaussian falloff: 1 at center, decaying with distance. */
function gaussian(dist: number, sigma: number): number {
  if (sigma <= 0) return dist <= 0 ? 1 : 0;
  return Math.exp(-(dist * dist) / (2 * sigma * sigma));
}

// -- layer definitions --

interface Layer {
  cx: number;
  cy: number;
  radius: number;
  color: RGB;
  blur: number;
  opacity: number;
  gradient?: {
    /** Center of the gradient (normalized coords). */
    gcx: number;
    gcy: number;
  };
  /** For the dark ring: radial gradient with transparent center, dark band, transparent edge. */
  ring?: boolean;
}

const BASE_COLOR: RGB = hexToRgb("#A1723A");

const LAYERS: Layer[] = [
  // 1: Dark maroon shadow
  {
    cx: 0.54,
    cy: 0.45,
    radius: 0.53,
    color: hexToRgb("#531002"),
    blur: 0.062,
    opacity: 1,
  },
  // 2: Blue body
  {
    cx: 0.6,
    cy: 0.38,
    radius: 0.43,
    color: hexToRgb("#2B5DF0"),
    blur: 0.124,
    opacity: 1,
  },
  // 3: Blue accent (gradient from center color to transparent)
  {
    cx: 0.59,
    cy: 0.38,
    radius: 0.45,
    color: hexToRgb("#387AFA"),
    blur: 0.046,
    opacity: 1,
    gradient: { gcx: 0.66, gcy: 0.26 },
  },
  // 4: Pink glow
  {
    cx: 0.66,
    cy: 0.27,
    radius: 0.23,
    color: hexToRgb("#FCB8D4"),
    blur: 0.093,
    opacity: 1,
  },
  // 5: White specular
  {
    cx: 0.66,
    cy: 0.27,
    radius: 0.09,
    color: hexToRgb("#FFFFFF"),
    blur: 0.062,
    opacity: 1,
  },
  // 6: Dark ring (transparent → black → transparent, opacity 0.9)
  {
    cx: 0.6,
    cy: 0.36,
    radius: 0.82,
    color: [0, 0, 0],
    blur: 0.046,
    opacity: 0.9,
    ring: true,
  },
];

// -- per-pixel compositing --

function computeLayerAlpha(
  nx: number,
  ny: number,
  layer: Layer,
): { alpha: number; color: RGB } {
  const dx = nx - layer.cx;
  const dy = ny - layer.cy;
  const dist = Math.sqrt(dx * dx + dy * dy);

  // Base radial extent with gaussian blur falloff at edge
  const radialFalloff = gaussian(Math.max(0, dist - layer.radius), layer.blur);

  if (layer.ring) {
    // Dark ring: peak opacity at ~70% of radius, fading to 0 at center and edge
    const normalizedDist = dist / layer.radius;
    // Ring peaks around 0.7 of the radius
    const ringProfile = gaussian(normalizedDist - 0.7, 0.15) * radialFalloff;
    return { alpha: ringProfile * layer.opacity, color: layer.color };
  }

  if (layer.gradient) {
    // Gradient: full color at gradient center, fading to transparent at edges
    const gdx = nx - layer.gradient.gcx;
    const gdy = ny - layer.gradient.gcy;
    const gDist = Math.sqrt(gdx * gdx + gdy * gdy);
    const gradientT = clamp(gDist / (layer.radius * 1.2), 0, 1);
    const alpha = radialFalloff * (1 - gradientT);
    return { alpha: alpha * layer.opacity, color: layer.color };
  }

  return { alpha: radialFalloff * layer.opacity, color: layer.color };
}

/**
 * Anti-aliased circle alpha for clipping.
 * Returns 0 outside, 1 inside, smooth transition at edge.
 */
export function circleAlpha(px: number, py: number, size: number): number {
  const cx = (size - 1) / 2;
  const cy = (size - 1) / 2;
  const r = size / 2;
  const dx = px - cx;
  const dy = py - cy;
  const dist = Math.sqrt(dx * dx + dy * dy);
  // 1px anti-aliasing band
  return clamp(r - dist + 0.5, 0, 1);
}

/**
 * Generate a size x size pixel grid of the Zora zorb.
 * Returns row-major RGB array (grid[y][x]).
 */
export function generateZorbPixels(size: number): RGB[][] {
  const grid: RGB[][] = [];

  for (let y = 0; y < size; y++) {
    const row: RGB[] = [];
    for (let x = 0; x < size; x++) {
      // Normalized coordinates [0, 1]
      const nx = x / (size - 1);
      const ny = y / (size - 1);

      // Start with base color
      let pixel: RGB = [...BASE_COLOR];

      // Composite each layer
      for (const layer of LAYERS) {
        const { alpha, color } = computeLayerAlpha(nx, ny, layer);
        if (alpha > 0.001) {
          pixel = alphaOver(pixel, color, alpha);
        }
      }

      // Clip to circle with anti-aliasing (blend to black for outside)
      const ca = circleAlpha(x, y, size);
      pixel = [
        Math.round(pixel[0] * ca),
        Math.round(pixel[1] * ca),
        Math.round(pixel[2] * ca),
      ];

      row.push(pixel);
    }
    grid.push(row);
  }

  return grid;
}
