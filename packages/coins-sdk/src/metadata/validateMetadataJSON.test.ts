import { describe, expect, it } from "vitest";
import { validateMetadataJSON } from "./validateMetadataJSON";

describe("validateMetadataJSON", () => {
  it("should validate metadata JSON", () => {
    expect(
      validateMetadataJSON({
        name: "horse",
        description: "boundless energy",
        image:
          "ipfs://bafybeigoxzqzbnxsn35vq7lls3ljxdcwjafxvbvkivprsodzrptpiguysy",
      }),
    ).toBe(true);
  });

  it("should fail to validate metadata JSON", () => {
    expect(() =>
      validateMetadataJSON({
        name: 32,
        description: "boundless energy",
        image:
          "ipfs://bafybeigoxzqzbnxsn35vq7lls3ljxdcwjafxvbvkivprsodzrptpiguysy",
      }),
    ).toThrow(new Error("Metadata name is required and must be a string"));
  });
});
