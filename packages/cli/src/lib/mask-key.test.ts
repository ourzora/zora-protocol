import { describe, it, expect } from "vitest";
import { maskKey } from "./mask-key.js";

describe("maskKey", () => {
  it("fully masks short keys (<=12 chars)", () => {
    expect(maskKey("abc")).toBe("***");
    expect(maskKey("123456789012")).toBe("***");
  });

  it("shows first 8 and last 4 for longer keys", () => {
    expect(maskKey("1234567890123")).toBe("12345678...0123");
    expect(maskKey("sk_live_abcdefghijklmnop")).toBe("sk_live_...mnop");
  });

  it("masks single-char key", () => {
    expect(maskKey("x")).toBe("***");
  });

  it("masks empty string", () => {
    expect(maskKey("")).toBe("***");
  });
});
