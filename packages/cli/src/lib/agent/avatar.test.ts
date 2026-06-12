import { describe, it, expect, vi, beforeEach } from "vitest";

vi.mock("node:fs", () => ({ readFileSync: vi.fn(), statSync: vi.fn() }));
vi.mock("./zora-client.js", () => ({ ipfsUpload: vi.fn() }));

import { loadAvatar, uploadAvatar } from "./avatar.js";
import { readFileSync, statSync } from "node:fs";
import { ipfsUpload } from "./zora-client.js";

const statOfSize = (size: number) =>
  ({ size }) as unknown as ReturnType<typeof statSync>;

beforeEach(() => {
  vi.clearAllMocks();
  // Default to a small, well-under-limit file; size-specific tests override it.
  vi.mocked(statSync).mockReturnValue(statOfSize(1024));
});

describe("loadAvatar", () => {
  it("reads a supported image and returns its bytes, base name, and MIME type", () => {
    vi.mocked(readFileSync).mockReturnValue(Buffer.from([1, 2, 3]));
    const file = loadAvatar("/some/dir/me.png");
    expect(file.filename).toBe("me.png");
    expect(file.mimeType).toBe("image/png");
    expect(Array.from(file.bytes)).toEqual([1, 2, 3]);
    expect(readFileSync).toHaveBeenCalledWith("/some/dir/me.png");
  });

  it("matches the extension case-insensitively", () => {
    vi.mocked(readFileSync).mockReturnValue(Buffer.from([0]));
    expect(loadAvatar("PIC.JPG").mimeType).toBe("image/jpeg");
    expect(loadAvatar("clip.JPEG").mimeType).toBe("image/jpeg");
    expect(loadAvatar("anim.GIF").mimeType).toBe("image/gif");
  });

  it("throws on an unsupported extension without touching the file", () => {
    expect(() => loadAvatar("notes.txt")).toThrow(/Unsupported avatar/);
    expect(statSync).not.toHaveBeenCalled();
    expect(readFileSync).not.toHaveBeenCalled();
  });

  it("throws when the image exceeds the size limit, without reading it", () => {
    vi.mocked(statSync).mockReturnValue(statOfSize(11 * 1024 * 1024));
    expect(() => loadAvatar("huge.png")).toThrow(/too large/);
    expect(readFileSync).not.toHaveBeenCalled();
  });
});

describe("uploadAvatar", () => {
  it("uploads the loaded bytes and returns the ipfs URI", async () => {
    vi.mocked(readFileSync).mockReturnValue(Buffer.from([9, 9]));
    vi.mocked(ipfsUpload).mockResolvedValue("ipfs://cid");
    const uri = await uploadAvatar("tok", "/x/pic.webp");
    expect(uri).toBe("ipfs://cid");
    expect(ipfsUpload).toHaveBeenCalledWith(
      "tok",
      "pic.webp",
      expect.any(Uint8Array),
      "image/webp",
    );
  });

  it("does not upload when the extension is unsupported", async () => {
    await expect(uploadAvatar("tok", "doc.pdf")).rejects.toThrow(
      /Unsupported avatar/,
    );
    expect(ipfsUpload).not.toHaveBeenCalled();
  });
});
