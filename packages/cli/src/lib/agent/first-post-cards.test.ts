import { describe, it, expect } from "vitest";
import { Buffer } from "node:buffer";
import { FIRST_POST_CARDS, pickFirstPostCard } from "./first-post-cards.js";

const PNG_MAGIC = [0x89, 0x50, 0x4e, 0x47];

describe("first-post cards", () => {
  it("bundles a non-empty set of cards", () => {
    expect(FIRST_POST_CARDS.length).toBeGreaterThanOrEqual(1);
  });

  it("each card has a greeting, an uppercase-alnum ticker, and a valid PNG", () => {
    for (const card of FIRST_POST_CARDS) {
      expect(card.greeting.length).toBeGreaterThan(0);
      expect(card.ticker).toMatch(/^[A-Z0-9]+$/);
      const png = Buffer.from(card.pngBase64, "base64");
      expect(png.length).toBeGreaterThan(100);
      expect([...png.subarray(0, 4)]).toEqual(PNG_MAGIC);
    }
  });

  it("pickFirstPostCard selects deterministically from the random fn", () => {
    expect(pickFirstPostCard(() => 0)).toBe(FIRST_POST_CARDS[0]);
    expect(pickFirstPostCard(() => 0.9999)).toBe(
      FIRST_POST_CARDS[FIRST_POST_CARDS.length - 1],
    );
  });

  it("defaults to a card from the bundled set", () => {
    expect(FIRST_POST_CARDS).toContain(pickFirstPostCard());
  });
});
