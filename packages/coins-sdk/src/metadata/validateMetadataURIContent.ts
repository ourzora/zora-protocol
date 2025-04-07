import {
  cleanAndValidateMetadataURI,
  ValidMetadataURI,
} from "./cleanAndValidateMetadataURI";
import { validateMetadataJSON } from "./validateMetadataJSON";

/**
 * Validate the metadata URI Content
 * @param metadataURI - The metadata URI to validate
 * @returns true if the metadata is valid, throws an error otherwise
 */
export async function validateMetadataURIContent(
  metadataURI: ValidMetadataURI,
) {
  const cleanedURI = cleanAndValidateMetadataURI(metadataURI);
  const response = await fetch(cleanedURI);
  if (!response.ok) {
    throw new Error("Metadata fetch failed");
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
