import { describe, it, expect } from "vitest";
import { generateZorbPixels, circleAlpha } from "./zorb-pixels.js";

describe("generateZorbPixels", () => {
  const size = 20;
  const grid = generateZorbPixels(size);

  it("returns a grid of the correct dimensions", () => {
    expect(grid).toHaveLength(size);
    for (const row of grid) {
      expect(row).toHaveLength(size);
    }
  });

  it("each pixel is a valid RGB tuple", () => {
    for (const row of grid) {
      for (const [r, g, b] of row) {
        expect(r).toBeGreaterThanOrEqual(0);
        expect(r).toBeLessThanOrEqual(255);
        expect(g).toBeGreaterThanOrEqual(0);
        expect(g).toBeLessThanOrEqual(255);
        expect(b).toBeGreaterThanOrEqual(0);
        expect(b).toBeLessThanOrEqual(255);
      }
    }
  });

  it("center pixel is blue-dominant", () => {
    const mid = Math.floor(size / 2);
    const [r, , b] = grid[mid][mid];
    expect(b).toBeGreaterThan(r);
  });

  it("upper-right area has a bright highlight", () => {
    // Specular highlight at ~(0.66, 0.27) → pixel (13, 5) for size 20
    const hx = Math.round(0.66 * (size - 1));
    const hy = Math.round(0.27 * (size - 1));
    const [r, g, b] = grid[hy][hx];
    const brightness = (r + g + b) / 3;
    expect(brightness).toBeGreaterThan(100);
  });

  it("corner pixels are black (outside circle)", () => {
    const [r0, g0, b0] = grid[0][0];
    expect(r0 + g0 + b0).toBe(0);

    const last = size - 1;
    const [r1, g1, b1] = grid[last][last];
    expect(r1 + g1 + b1).toBe(0);
  });
});

describe("circleAlpha", () => {
  it("returns 1 at the center", () => {
    expect(circleAlpha(10, 10, 20)).toBeCloseTo(1, 1);
  });

  it("returns 0 at far corners", () => {
    expect(circleAlpha(0, 0, 20)).toBe(0);
  });

  it("returns partial value at the edge", () => {
    const a = circleAlpha(0, 10, 20);
    expect(a).toBeGreaterThan(0);
    expect(a).toBeLessThan(1);
  });
});
