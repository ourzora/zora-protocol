import { readFileSync, statSync } from "node:fs";
import { basename, extname } from "node:path";
import { ipfsUpload } from "./zora-client.js";

/** Largest avatar image we'll buffer into memory and upload (10 MB). */
export const MAX_AVATAR_BYTES = 10 * 1024 * 1024;

/** Image MIME types Zora accepts for an avatar, keyed by lowercased extension. */
export const AVATAR_MIME_BY_EXT: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
};

/** A local image, read into memory and ready to upload. */
export interface AvatarFile {
  /** Base file name, used as the IPFS upload's filename. */
  filename: string;
  bytes: Uint8Array;
  mimeType: string;
}

/**
 * Read and validate a local image, returning its bytes and MIME type. Throws on
 * an unsupported extension, a file larger than {@link MAX_AVATAR_BYTES}, or an
 * unreadable file — call this before any network or on-chain work so a bad image
 * fails fast (account creation mints a real identity, so we never want to get
 * partway in and then choke on the image). `label` names the image in error
 * messages (e.g. "Avatar" / "Post image").
 */
export function loadImageFile(path: string, label = "Image"): AvatarFile {
  const mimeType = AVATAR_MIME_BY_EXT[extname(path).toLowerCase()];
  if (!mimeType) {
    throw new Error(
      `Unsupported ${label.toLowerCase()} "${path}". Use a PNG, JPG, GIF, or WebP file.`,
    );
  }
  // Check the size before buffering the whole file into memory (and before the
  // upload), so an oversized image fails fast with a clear message.
  const { size } = statSync(path);
  if (size > MAX_AVATAR_BYTES) {
    throw new Error(
      `${label} "${path}" is too large (${(size / 1_048_576).toFixed(1)} MB). The maximum is 10 MB.`,
    );
  }
  const bytes = new Uint8Array(readFileSync(path));
  return { filename: basename(path), bytes, mimeType };
}

/** Read and validate a local avatar image. See {@link loadImageFile}. */
export function loadAvatar(path: string): AvatarFile {
  return loadImageFile(path, "Avatar image");
}

/** Read a local image and upload it to IPFS, returning its `ipfs://` URI. */
export async function uploadAvatar(
  token: string,
  path: string,
): Promise<string> {
  const { filename, bytes, mimeType } = loadAvatar(path);
  return ipfsUpload(token, filename, bytes, mimeType);
}
