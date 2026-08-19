import { describe, it, expect } from "vitest";
import {
  validateTicker,
  TICKER_MIN_LENGTH,
  TICKER_MAX_LENGTH,
} from "./ticker.js";

describe("validateTicker", () => {
  it("accepts a valid alphanumeric ticker", () => {
    expect(validateTicker("GM")).toBeUndefined();
    expect(validateTicker("DOGE2")).toBeUndefined();
    expect(validateTicker("a".repeat(TICKER_MAX_LENGTH))).toBeUndefined();
  });

  it("trims surrounding whitespace before validating", () => {
    expect(validateTicker("  GM  ")).toBeUndefined();
  });

  it("rejects a ticker below the minimum length", () => {
    expect(validateTicker("A")).toMatch(/at least 2 characters/);
    expect(validateTicker("")).toMatch(/at least 2 characters/);
  });

  it("rejects a ticker over the maximum length", () => {
    expect(validateTicker("A".repeat(TICKER_MAX_LENGTH + 1))).toMatch(
      /20 characters or fewer/,
    );
  });

  it("rejects non-alphanumeric characters", () => {
    expect(validateTicker("GM!")).toMatch(/letters and numbers/);
    expect(validateTicker("MY COIN")).toMatch(/letters and numbers/);
    expect(validateTicker("café")).toMatch(/letters and numbers/);
  });

  it("exposes the limits it enforces", () => {
    expect(TICKER_MIN_LENGTH).toBe(2);
    expect(TICKER_MAX_LENGTH).toBe(20);
  });
});
