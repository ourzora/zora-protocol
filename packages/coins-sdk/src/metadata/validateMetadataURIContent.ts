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
  const metadataJson = await response.json();
  return validateMetadataJSON(metadataJson);
}
