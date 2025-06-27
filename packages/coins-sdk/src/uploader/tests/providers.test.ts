import { describe, expect, it, vi, beforeEach } from "vitest";
import { ZoraUploader, createZoraUploaderForCreator } from "../providers/zora";
import { setApiKey } from "../../api/api-key";

// Mock the fetch function
const mockFetch = vi.fn();
global.fetch = mockFetch;

// Mock console methods
console.log = vi.fn();
console.error = vi.fn();

describe("ZoraUploader", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockFetch.mockReset();
    setApiKey(undefined);
  });

  describe("constructor", () => {
    it("should initialize with provided API key", () => {
      setApiKey("test-api-key");
      const uploader = new ZoraUploader("0x123");
      expect(uploader).toBeDefined();
    });

    it("should throw if no API key is available", () => {
      expect(() => new ZoraUploader("0x123")).toThrow("API key is required");
    });
  });

  describe("upload", () => {
    it("should successfully upload a file with the zora uploader", async () => {
      // Mock JWT token creation response
      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          headers: new Headers({
            "Content-Type": "application/json",
            "Content-Length": "1000",
          }),
          json: async () => ({
            createUploadJwtFromApiKey: "test-jwt-token",
          }),
        })
        .mockResolvedValueOnce({
          ok: true,
          headers: new Headers({
            "Content-Type": "application/json",
          }),
          json: async () => ({
            cid: "bafybeiguslukdujd22p7ix53rcszgbg4ine464g33zk2st3lnjpx4uvmri",
            size: 100,
            mimeType: "image/png",
          }),
        });

      setApiKey("test-api-key");
      const uploader = new ZoraUploader("0x123");
      const file = new File(["test"], "test.png", { type: "image/png" });
      const result = await uploader.upload(file);

      // Verify fetch was called with correct parameters
      expect(mockFetch).toHaveBeenCalledTimes(2);
      expect(mockFetch).toHaveBeenCalledWith(
        "https://ipfs-uploader.zora.co/api/v0/add?cid-version=1",
        expect.objectContaining({
          method: "POST",
          headers: expect.objectContaining({
            Authorization: "Bearer test-jwt-token",
          }),
        }),
      );

      // Verify result
      expect(result).toEqual({
        url: "ipfs://bafybeiguslukdujd22p7ix53rcszgbg4ine464g33zk2st3lnjpx4uvmri",
        size: 100,
        mimeType: "image/png",
      });
    });

    it("should throw an error if upload fails", async () => {
      // Mock failed response
      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          headers: new Headers({
            "Content-Type": "application/json",
            "Content-Length": "1000",
          }),
          json: async () => ({
            createUploadJwtFromApiKey: "test-jwt-token",
          }),
        })
        .mockResolvedValueOnce({
          ok: false,
          statusText: "Bad Request",
          text: async () => "Invalid file",
        });

      setApiKey("test-api-key");
      const uploader = new ZoraUploader("0x123");
      const file = new File(["test"], "test.png", { type: "image/png" });

      await expect(uploader.upload(file)).rejects.toThrow(
        "Failed to upload file",
      );

      // Verify fetch was called with correct parameters
      expect(mockFetch).toHaveBeenCalledTimes(2);
      expect(mockFetch).toHaveBeenCalledWith(
        "https://ipfs-uploader.zora.co/api/v0/add?cid-version=1",
        expect.objectContaining({
          method: "POST",
          headers: expect.objectContaining({
            Authorization: "Bearer test-jwt-token",
          }),
        }),
      );
    });
  });

  describe("factory function", () => {
    it("should create a ZoraUploader instance", () => {
      setApiKey("test-api-key");
      const uploader = createZoraUploaderForCreator("0x123");
      expect(uploader).toBeInstanceOf(ZoraUploader);
    });
  });
});
