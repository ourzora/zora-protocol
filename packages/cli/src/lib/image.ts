import { extname } from "node:path";

/**
 * Image extensions accepted by the metadata uploader, mapped to their MIME type.
 * Shared by `coin create` and `coin edit` so the two validate image inputs
 * identically (the uploader only accepts PNG/JPEG/GIF/SVG).
 */
export const IMAGE_MIME_BY_EXT: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".svg": "image/svg+xml",
};

/**
 * Resolves the MIME type for a local image path from its extension, or `null`
 * when the extension isn't a supported image type. Case-insensitive.
 */
export function imageMimeForPath(path: string): string | null {
  const ext = extname(path).toLowerCase();
  return IMAGE_MIME_BY_EXT[ext] ?? null;
}
