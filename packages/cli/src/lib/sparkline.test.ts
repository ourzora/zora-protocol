import { describe, it, expect } from "vitest";
import { sparkline, downsample } from "./sparkline.js";

describe("sparkline", () => {
  it("returns empty string for empty array", () => {
    expect(sparkline([])).toBe("");
  });

  it("returns middle block for single value", () => {
    expect(sparkline([5])).toBe("▅");
  });

  it("renders ascending values as ascending blocks", () => {
    const result = sparkline([0, 1, 2, 3, 4, 5, 6, 7]);
    expect(result).toBe("▁▂▃▄▅▆▇█");
  });

  it("renders all same values as middle blocks", () => {
    const result = sparkline([5, 5, 5, 5]);
    expect(result).toBe("▅▅▅▅");
  });

  it("renders descending values as descending blocks", () => {
    const result = sparkline([7, 0]);
    expect(result).toBe("█▁");
  });

  it("handles negative values", () => {
    const result = sparkline([-10, 0, 10]);
    expect(result).toBe("▁▅█");
  });
});

describe("downsample", () => {
  it("returns original when under max width", () => {
    const values = [1, 2, 3];
    expect(downsample(values, 10)).toEqual(values);
  });

  it("reduces to max width by averaging buckets", () => {
    const values = [1, 3, 5, 7];
    const result = downsample(values, 2);
    expect(result).toHaveLength(2);
    expect(result[0]).toBe(2); // avg(1, 3)
    expect(result[1]).toBe(6); // avg(5, 7)
  });
});
