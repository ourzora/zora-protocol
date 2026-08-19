import { describe, it, expect } from "vitest";
import { renderFirstPostCard, CARD_SIZE } from "./render-card.js";

// A 2×2 red PNG (smallest valid raster), enough to exercise the full
// Satori → resvg pipeline without a fixture file.
const TINY_PNG = Buffer.from(
  "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEklEQVR4nGP8z8Dwn4EIwDiUFQEAA1cD/9V8x8gAAAAASUVORK5CYII=",
  "base64",
);

/** Read a big-endian uint32 from a PNG IHDR chunk. */
function pngDimensions(png: Buffer): { width: number; height: number } {
  // PNG signature (8) + length (4) + "IHDR" (4) → width @16, height @20.
  return { width: png.readUInt32BE(16), height: png.readUInt32BE(20) };
}

describe("renderFirstPostCard", () => {
  it("renders a 1500×1500 PNG from a caption, image, and handle", async () => {
    const png = await renderFirstPostCard({
      image: new Uint8Array(TINY_PNG),
      mimeType: "image/png",
      caption: "i am simply a happy little creature",
      handle: "zora.co/test",
    });

    // PNG magic bytes.
    expect(png.subarray(0, 8)).toEqual(
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    );
    expect(png.length).toBeGreaterThan(1000);
    expect(pngDimensions(png)).toEqual({
      width: CARD_SIZE,
      height: CARD_SIZE,
    });
  });

  it("handles an emoji-bearing caption without throwing", async () => {
    const png = await renderFirstPostCard({
      image: new Uint8Array(TINY_PNG),
      mimeType: "image/png",
      caption: "found five dollars 💸 and now i forgive everyone 🙏",
      handle: "zora.co/another",
    });
    expect(png.length).toBeGreaterThan(1000);
  });
});
