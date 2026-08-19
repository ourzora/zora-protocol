import {
  cleanAndValidateMetadataURI,
  type ValidMetadataURI,
} from "@zoralabs/coins-sdk";

/**
 * A coin's metadata JSON, as stored at its `contractURI`. We model only the
 * fields this command reads or writes; every other field (`animation_url`,
 * `content`, `properties`, `symbol`, …) is preserved verbatim, so the shape is
 * left open.
 */
export type CoinMetadata = Record<string, unknown> & {
  name?: string;
  description?: string;
  image?: string;
};

/** The metadata fields `coin edit` can change. An `undefined` field is left untouched. */
export interface MetadataEdits {
  /** New caption/description. */
  description?: string;
  /** New image URI (already uploaded to IPFS, e.g. `ipfs://…`). */
  imageUri?: string;
}

/**
 * Fetch a coin's current metadata JSON from its `tokenUri` (the `contractURI`).
 *
 * `ipfs://`/`ar://` URIs are resolved to an HTTPS gateway via the coins-sdk
 * helper — the same resolution the Zora app uses. Gateways are inconsistent
 * about the `Content-Type` they return for pinned JSON, so we parse the body
 * as JSON directly and fall back to parsing it as text rather than trusting
 * the header.
 */
export async function fetchCoinMetadata(
  tokenUri: string,
): Promise<CoinMetadata> {
  const url = cleanAndValidateMetadataURI(tokenUri as ValidMetadataURI);

  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Failed to fetch coin metadata (HTTP ${res.status}).`);
  }

  const text = await res.text();
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error("Coin metadata is not valid JSON.");
  }

  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    throw new Error("Coin metadata is not a JSON object.");
  }
  return parsed as CoinMetadata;
}

/**
 * Produce the metadata to upload for an edit: a shallow copy of the existing
 * metadata with the edited fields applied. Only `image` and `description` are
 * editable here — the name/ticker and every other field are preserved, mirroring
 * the Zora app's "Edit post" (which keeps the title fixed for coins).
 *
 * The input is not mutated. A missing description is normalized to an empty
 * string so the result is always valid coin metadata. Throws if the coin has no
 * image to carry over (i.e. it isn't an editable post).
 */
export function mergeMetadata(
  previous: CoinMetadata,
  edits: MetadataEdits,
): CoinMetadata {
  const next: CoinMetadata = { ...previous };

  if (edits.imageUri !== undefined) {
    next.image = edits.imageUri;
  }
  if (edits.description !== undefined) {
    next.description = edits.description;
  }
  if (typeof next.description !== "string") {
    next.description = "";
  }

  if (typeof next.image !== "string" || next.image.length === 0) {
    throw new Error(
      "This coin has no image, so there's nothing to preserve — only posts with an image can be edited.",
    );
  }

  return next;
}
