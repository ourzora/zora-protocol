import { describe, expect, it, vi, beforeEach } from "vitest";
import { ZoraUploader, createZoraUploaderForCreator } from "../providers/zora";
import { setApiKey } from "../../api/api-key";

// Mock the fetch function
const mockFetch = vi.fn();
global.fetch = mockFetch;

// Mock console methods
console.log = vi.fn();
console.error = vi.fn();

function mockJwtResponse(jwt = "test-jwt-token") {
  return {
    ok: true,
    headers: new Headers({
      "Content-Type": "application/json",
      "Content-Length": "1000",
    }),
    json: async () => ({
      createUploadJwtFromApiKey: jwt,
    }),
  };
}

function mockUploadResponse(
  cid = "bafybeiguslukdujd22p7ix53rcszgbg4ine464g33zk2st3lnjpx4uvmri",
) {
  return {
    ok: true,
    status: 200,
    headers: new Headers({
      "Content-Type": "application/json",
    }),
    json: async () => ({
      cid,
      size: 100,
      mimeType: "image/png",
    }),
  };
}

function mock401Response() {
  return {
    ok: false,
    status: 401,
    statusText: "Unauthorized",
    text: async () => "Unauthorized",
  };
}

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
      mockFetch
        .mockResolvedValueOnce(mockJwtResponse())
        .mockResolvedValueOnce(mockUploadResponse());

      setApiKey("test-api-key");
      const uploader = new ZoraUploader("0x123");
      const file = new File(["test"], "test.png", { type: "image/png" });
      const result = await uploader.upload(file);

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

      expect(result).toEqual({
        url: "ipfs://bafybeiguslukdujd22p7ix53rcszgbg4ine464g33zk2st3lnjpx4uvmri",
        size: 100,
        mimeType: "image/png",
      });
    });

    it("should throw an error if upload fails with non-401 status", async () => {
      mockFetch.mockResolvedValueOnce(mockJwtResponse()).mockResolvedValueOnce({
        ok: false,
        status: 400,
        statusText: "Bad Request",
        text: async () => "Invalid file",
      });

      setApiKey("test-api-key");
      const uploader = new ZoraUploader("0x123");
      const file = new File(["test"], "test.png", { type: "image/png" });

      await expect(uploader.upload(file)).rejects.toThrow(
        "Failed to upload file",
      );

      // Should NOT retry on non-401 errors
      expect(mockFetch).toHaveBeenCalledTimes(2); // 1 JWT + 1 upload
    });

    it("should retry once on 401 with a fresh JWT", async () => {
      mockFetch
        // First JWT fetch
        .mockResolvedValueOnce(mockJwtResponse("stale-jwt"))
        // First upload returns 401
        .mockResolvedValueOnce(mock401Response())
        // Second JWT fetch (refresh)
        .mockResolvedValueOnce(mockJwtResponse("fresh-jwt"))
        // Retry upload succeeds
        .mockResolvedValueOnce(mockUploadResponse());

      setApiKey("test-api-key");
      const uploader = new ZoraUploader("0x123");
      const file = new File(["test"], "test.png", { type: "image/png" });
      const result = await uploader.upload(file);

      expect(mockFetch).toHaveBeenCalledTimes(4); // 2 JWT + 2 upload

      // Verify the retry used the fresh JWT
      const lastUploadCall = mockFetch.mock.calls[3];
      expect(lastUploadCall[1].headers.Authorization).toBe("Bearer fresh-jwt");

      expect(result).toEqual({
        url: "ipfs://bafybeiguslukdujd22p7ix53rcszgbg4ine464g33zk2st3lnjpx4uvmri",
        size: 100,
        mimeType: "image/png",
      });
    });

    it("should throw if retry after 401 also fails", async () => {
      mockFetch
        .mockResolvedValueOnce(mockJwtResponse("stale-jwt"))
        .mockResolvedValueOnce(mock401Response())
        .mockResolvedValueOnce(mockJwtResponse("also-bad-jwt"))
        .mockResolvedValueOnce({
          ok: false,
          status: 403,
          statusText: "Forbidden",
          text: async () => "Forbidden",
        });

      setApiKey("test-api-key");
      const uploader = new ZoraUploader("0x123");
      const file = new File(["test"], "test.png", { type: "image/png" });

      await expect(uploader.upload(file)).rejects.toThrow(
        "Failed to upload file",
      );

      expect(mockFetch).toHaveBeenCalledTimes(4);
    });

    it("should reuse cached JWT for subsequent uploads", async () => {
      mockFetch
        .mockResolvedValueOnce(mockJwtResponse())
        .mockResolvedValueOnce(mockUploadResponse())
        .mockResolvedValueOnce(mockUploadResponse());

      setApiKey("test-api-key");
      const uploader = new ZoraUploader("0x123");
      const file1 = new File(["test1"], "test1.png", { type: "image/png" });
      const file2 = new File(["test2"], "test2.png", { type: "image/png" });

      await uploader.upload(file1);
      await uploader.upload(file2);

      // Only 1 JWT fetch + 2 uploads
      expect(mockFetch).toHaveBeenCalledTimes(3);
    });

    it("should pass signal to upload request", async () => {
      mockFetch
        .mockResolvedValueOnce(mockJwtResponse())
        .mockResolvedValueOnce(mockUploadResponse());

      setApiKey("test-api-key");
      const uploader = new ZoraUploader("0x123");
      const file = new File(["test"], "test.png", { type: "image/png" });
      const controller = new AbortController();

      await uploader.upload(file, { signal: controller.signal });

      const uploadCall = mockFetch.mock.calls[1];
      expect(uploadCall[1].signal).toBe(controller.signal);
    });

    it("should pass timeout as AbortSignal to upload request", async () => {
      mockFetch
        .mockResolvedValueOnce(mockJwtResponse())
        .mockResolvedValueOnce(mockUploadResponse());

      setApiKey("test-api-key");
      const uploader = new ZoraUploader("0x123");
      const file = new File(["test"], "test.png", { type: "image/png" });

      await uploader.upload(file, { timeout: 30_000 });

      const uploadCall = mockFetch.mock.calls[1];
      expect(uploadCall[1].signal).toBeDefined();
    });

    it("should pass combined signal when both signal and timeout are provided", async () => {
      mockFetch
        .mockResolvedValueOnce(mockJwtResponse())
        .mockResolvedValueOnce(mockUploadResponse());

      setApiKey("test-api-key");
      const uploader = new ZoraUploader("0x123");
      const file = new File(["test"], "test.png", { type: "image/png" });
      const controller = new AbortController();

      await uploader.upload(file, {
        signal: controller.signal,
        timeout: 30_000,
      });

      const uploadCall = mockFetch.mock.calls[1];
      // When both signal and timeout are provided, AbortSignal.any() is used
      // so the resulting signal is different from the original
      expect(uploadCall[1].signal).toBeDefined();
      expect(uploadCall[1].signal).not.toBe(controller.signal);
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
