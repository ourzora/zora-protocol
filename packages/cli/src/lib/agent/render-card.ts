import { Buffer } from "node:buffer";
import { createElement } from "react";
import satori, { init as initSatori } from "satori/standalone";
import { initWasm, Resvg } from "@resvg/resvg-wasm";
import { MONUMENT_MEDIUM, MONUMENT_REGULAR } from "./card-fonts.js";
import { RESVG_WASM, YOGA_WASM } from "./card-wasm.js";

/** The brand meme template is a fixed 1500×1500 square. */
export const CARD_SIZE = 1500;

const FONT_FAMILY = "ABC Monument Grotesk";

/**
 * Lazily initialize the two WASM engines exactly once. Satori's Yoga layout
 * engine and resvg's rasterizer each need their module loaded before first use;
 * we feed them the inlined bytes so this works in both the Node CLI and the
 * compiled bun binary. Concurrent callers share the same in-flight promise.
 */
let enginesReady: Promise<void> | undefined;
function ensureEngines(): Promise<void> {
  if (!enginesReady) {
    enginesReady = Promise.all([
      initSatori(YOGA_WASM),
      initWasm(RESVG_WASM),
    ]).then(() => undefined);
    // Cache the in-flight promise synchronously so concurrent callers share it,
    // but clear it on failure — caching a rejected promise would permanently
    // poison the module, since the `if (!enginesReady)` guard never re-runs.
    enginesReady.catch(() => {
      enginesReady = undefined;
    });
  }
  return enginesReady;
}

export interface CardInput {
  /** Raw bytes of the background photo (PNG/JPG/GIF/WebP). */
  image: Uint8Array;
  /** MIME type of the background photo, used to build the data URI. */
  mimeType: string;
  /** The big centered meme caption. */
  caption: string;
  /** The faint bottom handle, e.g. "zora.co/alice". */
  handle: string;
}

/** Build the data URI Satori embeds as the stretched-to-fill background image. */
function imageDataUri(bytes: Uint8Array, mimeType: string): string {
  return `data:${mimeType};base64,${Buffer.from(bytes).toString("base64")}`;
}

/**
 * Render the first-post card to a PNG buffer, matching the brand Figma template
 * (node 2289:316): a background photo stretched to fill the full 1500×1500 square
 * (de-shaped to 1:1, not cropped or letterboxed — the intentional meme look), a
 * large centered caption in ABC Monument Grotesk Medium, and a faint bottom
 * handle in Regular.
 *
 * Layout/type values mirror the template scaled to its native 1500×1500 frame.
 */
export async function renderFirstPostCard(input: CardInput): Promise<Buffer> {
  await ensureEngines();

  // Background photo stretched to fill the full square via backgroundSize
  // "100% 100%", which reliably distorts the source to 1:1 (de-shaped, not
  // cropped or letterboxed). Satori's <img> objectFit is finicky here, so we
  // use a <div> background — backgroundSize always stretches to the box.
  const background = createElement("div", {
    style: {
      position: "absolute",
      top: 0,
      left: 0,
      width: CARD_SIZE,
      height: CARD_SIZE,
      backgroundImage: `url(${imageDataUri(input.image, input.mimeType)})`,
      backgroundSize: "100% 100%",
      backgroundRepeat: "no-repeat",
    },
  });

  // Caption: vertically + horizontally centered, ~1334px text column (the
  // template's 83px side inset on a 1500px frame).
  const caption = createElement(
    "div",
    {
      style: {
        position: "absolute",
        top: 0,
        left: 0,
        width: CARD_SIZE,
        height: CARD_SIZE,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        padding: "0 83px",
      },
    },
    createElement(
      "div",
      {
        style: {
          fontFamily: FONT_FAMILY,
          fontWeight: 500,
          fontSize: 130,
          lineHeight: 0.9,
          letterSpacing: -3.9,
          color: "#ffffff",
          textAlign: "center",
          textShadow: "0px 4px 4px rgba(0,0,0,0.5)",
        },
      },
      input.caption,
    ),
  );

  // Handle: faint, pinned near the bottom edge, centered.
  const handle = createElement(
    "div",
    {
      style: {
        position: "absolute",
        bottom: 30,
        left: 0,
        width: CARD_SIZE,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      },
    },
    createElement(
      "div",
      {
        style: {
          fontFamily: FONT_FAMILY,
          fontWeight: 400,
          fontSize: 66,
          lineHeight: 0.9,
          letterSpacing: -1.98,
          color: "rgba(242,242,242,0.5)",
          textAlign: "center",
          textShadow: "0px 0px 25px rgba(0,0,0,0.25)",
        },
      },
      input.handle,
    ),
  );

  const root = createElement(
    "div",
    {
      style: {
        display: "flex",
        position: "relative",
        width: CARD_SIZE,
        height: CARD_SIZE,
      },
    },
    background,
    caption,
    handle,
  );

  const svg = await satori(root, {
    width: CARD_SIZE,
    height: CARD_SIZE,
    fonts: [
      {
        name: FONT_FAMILY,
        data: MONUMENT_REGULAR,
        weight: 400,
        style: "normal",
      },
      {
        name: FONT_FAMILY,
        data: MONUMENT_MEDIUM,
        weight: 500,
        style: "normal",
      },
    ],
  });

  const png = new Resvg(svg, { fitTo: { mode: "original" } }).render().asPng();
  return Buffer.from(png);
}
