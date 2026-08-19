import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { fetchCoinMetadata, mergeMetadata } from "./edit.js";

const IMAGE = "ipfs://bafyimageOld";
const NEW_IMAGE = "ipfs://bafyimageNew";

const baseMetadata = {
  name: "My Post",
  symbol: "POST",
  description: "old caption",
  image: IMAGE,
  animation_url: "ipfs://bafyvideo",
  content: { uri: "ipfs://bafyvideo", mime: "video/mp4" },
  properties: { category: "social" },
};

describe("fetchCoinMetadata", () => {
  const fetchMock = vi.fn();

  beforeEach(() => {
    vi.stubGlobal("fetch", fetchMock);
  });
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.clearAllMocks();
  });

  it("resolves an ipfs:// URI through the Zora gateway and returns the parsed object", async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 200,
      text: async () => JSON.stringify(baseMetadata),
    });

    const result = await fetchCoinMetadata("ipfs://bafymeta");

    expect(fetchMock).toHaveBeenCalledWith(
      "https://magic.decentralized-content.com/ipfs/bafymeta",
    );
    expect(result).toEqual(baseMetadata);
  });

  it("throws on a non-OK response", async () => {
    fetchMock.mockResolvedValue({
      ok: false,
      status: 404,
      text: async () => "",
    });
    await expect(fetchCoinMetadata("ipfs://bafymeta")).rejects.toThrow(
      "HTTP 404",
    );
  });

  it("throws when the body is not valid JSON", async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 200,
      text: async () => "not json",
    });
    await expect(fetchCoinMetadata("ipfs://bafymeta")).rejects.toThrow(
      "not valid JSON",
    );
  });

  it("throws when the body is JSON but not an object", async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      status: 200,
      text: async () => "[1,2,3]",
    });
    await expect(fetchCoinMetadata("ipfs://bafymeta")).rejects.toThrow(
      "not a JSON object",
    );
  });
});

describe("mergeMetadata", () => {
  it("replaces the image and preserves every other field", () => {
    const result = mergeMetadata(baseMetadata, { imageUri: NEW_IMAGE });
    expect(result).toEqual({ ...baseMetadata, image: NEW_IMAGE });
  });

  it("replaces the description and preserves every other field", () => {
    const result = mergeMetadata(baseMetadata, { description: "new caption" });
    expect(result).toEqual({ ...baseMetadata, description: "new caption" });
  });

  it("applies both edits at once", () => {
    const result = mergeMetadata(baseMetadata, {
      imageUri: NEW_IMAGE,
      description: "new caption",
    });
    expect(result.image).toBe(NEW_IMAGE);
    expect(result.description).toBe("new caption");
    // Name/ticker and media are never touched.
    expect(result.name).toBe("My Post");
    expect(result.symbol).toBe("POST");
    expect(result.animation_url).toBe("ipfs://bafyvideo");
  });

  it("leaves the description unchanged when no description edit is given", () => {
    const result = mergeMetadata(baseMetadata, { imageUri: NEW_IMAGE });
    expect(result.description).toBe("old caption");
  });

  it("allows clearing the description with an empty string", () => {
    const result = mergeMetadata(baseMetadata, { description: "" });
    expect(result.description).toBe("");
  });

  it("normalizes a missing description to an empty string", () => {
    const { description, ...withoutDescription } = baseMetadata;
    void description;
    const result = mergeMetadata(withoutDescription, { imageUri: NEW_IMAGE });
    expect(result.description).toBe("");
  });

  it("does not mutate the input", () => {
    const input = { ...baseMetadata };
    mergeMetadata(input, { imageUri: NEW_IMAGE, description: "x" });
    expect(input.image).toBe(IMAGE);
    expect(input.description).toBe("old caption");
  });

  it("throws when the coin has no image to carry over and none is supplied", () => {
    const { image, ...withoutImage } = baseMetadata;
    void image;
    expect(() => mergeMetadata(withoutImage, { description: "x" })).toThrow(
      "no image",
    );
  });
});
