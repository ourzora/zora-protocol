import { cleanAndValidateMetadataURI } from "./cleanAndValidateMetadataURI";
import { ValidMetadataURI } from "../uploader/types";
import { validateMetadataJSON } from "./validateMetadataJSON";

/**
 * Validate the metadata URI Content
 * @param metadataURI - The metadata URI to validate
 * @returns true if the metadata is valid, throws an error otherwise
 */
export async function validateMetadataURIContent(
  metadataURI: ValidMetadataURI,
) {
  let response: Response;
  const cleanedURI = cleanAndValidateMetadataURI(metadataURI);

  try {
    response = await fetch(cleanedURI);
  } catch (error) {
    // handle actual fetch failures (i.e. network errors)
    const errorMessage = error instanceof Error ? error.message : String(error);
    throw new Error(
      `Metadata fetch failed for URL '${cleanedURI}': ${errorMessage}`,
    );
  }

  if (!response.ok) {
    throw new Error(
      `Metadata fetch failed for URL '${cleanedURI}': ${response.statusText ? `${response.statusText} (HTTP ${response.status})` : `HTTP ${response.status}`}`,
    );
  }

  if (
    !["application/json", "text/plain"].includes(
      response.headers.get("content-type") ?? "",
    )
  ) {
    throw new Error("Metadata is not a valid JSON or plain text response type");
  }

  const metadataJson = await response.json();
  return validateMetadataJSON(metadataJson);
}
