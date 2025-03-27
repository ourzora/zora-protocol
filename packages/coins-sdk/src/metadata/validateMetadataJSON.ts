export type ValidMetadataJSON = {
  name: string;
  description: string;
  image: string;
  animation_url?: string;
  content?: { uri: string; mime?: string };
};

/**
 * Validate the metadata JSON object
 * @param metadata - The metadata object to validate
 */
export function validateMetadataJSON(metadata: ValidMetadataJSON | unknown) {
  if (typeof metadata !== "object" || !metadata) {
    throw new Error("Metadata must be an object and exist");
  }
  if (typeof (metadata as { name: unknown }).name !== "string") {
    throw new Error("Metadata name is required and must be a string");
  }
  if (typeof (metadata as { description: unknown }).description !== "string") {
    throw new Error("Metadata description is required and must be a string");
  }
  if (typeof (metadata as { image: unknown }).image === "string") {
  } else {
    throw new Error("Metadata image is required and must be a string");
  }
  if (
    "animation_url" in metadata &&
    typeof (metadata as { animation_url?: unknown }).animation_url !== "string"
  ) {
    throw new Error("Metadata animation_url, if provided, must be a string");
  }
  const content =
    "content" in metadata && (metadata as { content?: unknown }).content;
  if (content) {
    if (typeof (content as { uri?: unknown }).uri !== "string") {
      throw new Error("If provided, content.uri must be a string");
    }
    if (typeof (content as { mime?: unknown }).mime !== "string") {
      throw new Error("If provided, content.mime must be a string");
    }
  }

  return true;
}
