import { describe, expect, it, vi, beforeEach } from "vitest";
import {
  CoinMetadataBuilder,
  validateImageMimeType,
  getURLFromUploadResult,
} from "../metadata";
import { Uploader, UploadResult } from "../types";

enum UploadResultType {
  Image = "image",
  Media = "media",
  Metadata = "metadata",
}

// Create a mock implementation of the Uploader interface
const createMockUploader = (resultList: UploadResultType[]) => {
  // Pre-defined results to return from the upload method
  const mockImageResult: UploadResult = {
    url: "ipfs://image-cid",
    size: 100,
    mimeType: "image/png",
  };

  const mockMediaResult: UploadResult = {
    url: "ipfs://media-cid",
    size: 200,
    mimeType: "video/mp4",
  };

  const mockMetadataResult: UploadResult = {
    url: "ipfs://metadata-cid",
    size: 300,
    mimeType: "application/json",
  };

  const uploadedFiles: File[] = [];
  let callCount = 0;

  const mockUploader: Uploader = {
    upload: vi.fn(async (file: File): Promise<UploadResult> => {
      uploadedFiles.push(file);
      callCount++;

      switch (resultList[callCount - 1]) {
        case UploadResultType.Image:
          return mockImageResult;
        case UploadResultType.Media:
          return mockMediaResult;
        case UploadResultType.Metadata:
          return mockMetadataResult;
        default:
          throw new Error(`Invalid result type: ${resultList[callCount - 1]}`);
      }
    }),
  };

  return {
    uploader: mockUploader,
    uploadedFiles,
    mockImageResult,
    mockMediaResult,
    mockMetadataResult,
    reset: () => {
      callCount = 0;
      uploadedFiles.length = 0;
      vi.clearAllMocks();
    },
  };
};

describe("validateImageMimeType", () => {
  it("should not throw for valid image types", () => {
    const validTypes = [
      "image/png",
      "image/jpeg",
      "image/jpg",
      "image/gif",
      "image/svg+xml",
    ];

    validTypes.forEach((type) => {
      expect(() => validateImageMimeType(type)).not.toThrow();
    });
  });

  it("should throw for invalid image types", () => {
    const invalidTypes = ["image/webp", "application/pdf", "text/plain"];

    invalidTypes.forEach((type) => {
      expect(() => validateImageMimeType(type)).toThrow(
        "Image must be a PNG, JPEG, JPG, GIF or SVG",
      );
    });
  });
});

describe("getURLFromUploadResult", () => {
  it("should convert an upload result URL to a URL object", () => {
    const result: UploadResult = {
      url: "ipfs://bafybeiguslukdujd22p7ix53rcszgbg4ine464g33zk2st3lnjpx4uvmri",
      size: 100,
      mimeType: "image/png",
    };

    const url = getURLFromUploadResult(result);
    expect(url).toBeInstanceOf(URL);
    expect(url.toString()).toBe(
      "ipfs://bafybeiguslukdujd22p7ix53rcszgbg4ine464g33zk2st3lnjpx4uvmri",
    );
  });

  it("should throw for invalid URLs", () => {
    const result: UploadResult = {
      url: "invalid-url",
      size: 100,
      mimeType: "image/png",
    };

    expect(() => getURLFromUploadResult(result)).toThrow();
  });
});

describe("CoinMetadataBuilder", () => {
  let mockUploaderData: ReturnType<typeof createMockUploader>;
  let builder: CoinMetadataBuilder;

  beforeEach(() => {
    mockUploaderData = createMockUploader([
      UploadResultType.Image,
      UploadResultType.Media,
      UploadResultType.Metadata,
    ]);
    builder = new CoinMetadataBuilder();
  });

  describe("builder methods", () => {
    it("should set name and return self", () => {
      const result = builder.withName("Test Coin");
      expect(result).toBe(builder);
    });

    it("should set symbol and return self", () => {
      const result = builder.withSymbol("TEST");
      expect(result).toBe(builder);
    });

    it("should set description and return self", () => {
      const result = builder.withDescription("Test Description");
      expect(result).toBe(builder);
    });

    it("should set image file and return self", () => {
      const imageFile = new File(["test"], "test.png", { type: "image/png" });
      const result = builder.withImage(imageFile);
      expect(result).toBe(builder);
    });

    it("should throw if image URL is already set when setting image file", () => {
      builder.withImageURI("ipfs://test");
      const imageFile = new File(["test"], "test.png", { type: "image/png" });
      expect(() => builder.withImage(imageFile)).toThrow(
        "Image URL already set",
      );
    });

    it("should throw if image file is already set when setting image URI", () => {
      const imageFile = new File(["test"], "test.png", { type: "image/png" });
      builder.withImage(imageFile);
      expect(() => builder.withImageURI("ipfs://test")).toThrow(
        "Image file already set",
      );
    });

    it("should set media file and return self", () => {
      const mediaFile = new File(["test"], "test.mp4", { type: "video/mp4" });
      const result = builder.withMedia(mediaFile);
      expect(result).toBe(builder);
    });

    it("should throw if media URL is already set when setting media file", () => {
      builder.withMediaURI("ipfs://test", "video/mp4");
      const mediaFile = new File(["test"], "test.mp4", { type: "video/mp4" });
      expect(() => builder.withMedia(mediaFile)).toThrow(
        "Media URL already set",
      );
    });

    it("should throw if media file is already set when setting media URI", () => {
      const mediaFile = new File(["test"], "test.mp4", { type: "video/mp4" });
      builder.withMedia(mediaFile);
      expect(() => builder.withMediaURI("ipfs://test", "video/mp4")).toThrow(
        "Media file already set",
      );
    });

    it("should set properties and return self", () => {
      const properties = { key1: "value1", key2: "value2" };
      const result = builder.withProperties(properties);
      expect(result).toBe(builder);
    });

    it("should throw if property value is not a string", () => {
      const properties = { key1: "value1", key2: 123 as any };
      expect(() => builder.withProperties(properties)).toThrow(
        "Property value must be a string",
      );
    });
  });

  describe("validate", () => {
    it("should throw if name is not set", () => {
      builder
        .withSymbol("TEST")
        .withImage(new File(["test"], "test.png", { type: "image/png" }));
      expect(() => builder.validate()).toThrow("Name is required");
    });

    it("should throw if symbol is not set", () => {
      builder
        .withName("Test Coin")
        .withImage(new File(["test"], "test.png", { type: "image/png" }));
      expect(() => builder.validate()).toThrow("Symbol is required");
    });

    it("should throw if image is not set", () => {
      builder.withName("Test Coin").withSymbol("TEST");
      expect(() => builder.validate()).toThrow("Image is required");
    });

    it("should not throw if all required fields are set", () => {
      builder
        .withName("Test Coin")
        .withSymbol("TEST")
        .withImage(new File(["test"], "test.png", { type: "image/png" }));

      expect(() => builder.validate()).not.toThrow();
    });
  });

  describe("generateMetadata", () => {
    it("should generate correct metadata", () => {
      builder
        .withName("Test Coin")
        .withSymbol("TEST")
        .withDescription("Test Description")
        .withImageURI("ipfs://image-cid")
        .withMediaURI("ipfs://media-cid", "video/mp4")
        .withProperties({ key1: "value1", key2: "value2" });

      const metadata = builder.generateMetadata();

      expect(metadata).toEqual({
        name: "Test Coin",
        symbol: "TEST",
        description: "Test Description",
        image: "ipfs://image-cid",
        animation_url: "ipfs://media-cid",
        content: {
          uri: "ipfs://media-cid",
          mime: "video/mp4",
        },
        properties: { key1: "value1", key2: "value2" },
      });
    });
  });

  describe("upload", () => {
    it("should upload image, media and metadata", async () => {
      const imageFile = new File(["test-image"], "test.png", {
        type: "image/png",
      });
      const mediaFile = new File(["test-media"], "test.mp4", {
        type: "video/mp4",
      });

      builder
        .withName("Test Coin")
        .withSymbol("TEST")
        .withDescription("Test Description")
        .withImage(imageFile)
        .withMedia(mediaFile)
        .withProperties({ key1: "value1", key2: "value2" });

      const result = await builder.upload(mockUploaderData.uploader);

      // Verify uploader was called 3 times
      expect(mockUploaderData.uploader.upload).toHaveBeenCalledTimes(3);

      // Verify files were uploaded in the right order
      expect(mockUploaderData.uploadedFiles[0]).toBe(imageFile);
      expect(mockUploaderData.uploadedFiles[1]).toBe(mediaFile);
      expect(mockUploaderData.uploadedFiles[2]?.type).toBe("application/json");

      // Verify result
      expect(result.url.toString()).toBe("ipfs://metadata-cid");
    });

    it("should use existing image and media URLs if provided", async () => {
      mockUploaderData = createMockUploader([UploadResultType.Metadata]);
      builder = new CoinMetadataBuilder();

      builder
        .withName("Test Coin")
        .withSymbol("TEST")
        .withDescription("Test Description")
        .withImageURI("ipfs://existing-image")
        .withMediaURI("ipfs://existing-media", "video/mp4")
        .withProperties({ key1: "value1", key2: "value2" });

      const result = await builder.upload(mockUploaderData.uploader);

      // Should only upload metadata (1 upload)
      expect(mockUploaderData.uploader.upload).toHaveBeenCalledTimes(1);

      // The upload should be the metadata
      expect(mockUploaderData.uploadedFiles[0]?.type).toBe("application/json");

      // Verify result
      expect(result.url.toString()).toBe("ipfs://metadata-cid");
    });

    it("should validate before uploading", async () => {
      // Missing required fields
      builder.withName("Test Coin");

      await expect(builder.upload(mockUploaderData.uploader)).rejects.toThrow(
        "Symbol is required",
      );
    });
  });
});
