import { Address } from "viem";
import { Uploader, UploadResult } from "../types";
import { getApiKey } from "../../api/api-key";
import { setCreateUploadJwt } from "../../api/internal";

/**
 * Zora IPFS uploader implementation
 */
export class ZoraUploader implements Uploader {
  constructor(creatorAddress: Address) {
    this.creatorAddress = creatorAddress;
    if (!getApiKey()) {
      throw new Error("API key is required for metadata interactions");
    }
  }

  private creatorAddress: Address;
  private jwtApiKey: string | undefined;
  private jwtApiKeyExpiresAt: number | undefined;

  async getJWTApiKey() {
    if (
      this.jwtApiKey &&
      this.jwtApiKeyExpiresAt &&
      this.jwtApiKeyExpiresAt > Date.now()
    ) {
      return this.jwtApiKey;
    }
    // Expires in 1 hour
    this.jwtApiKeyExpiresAt = Date.now() + 1000 * 60 * 60;

    const response = await setCreateUploadJwt({
      creatorAddress: this.creatorAddress,
    });
    this.jwtApiKey = response.data?.createUploadJwtFromApiKey;
    if (!this.jwtApiKey) {
      throw new Error("Failed to create upload JWT");
    }

    return this.jwtApiKey;
  }

  async upload(file: File): Promise<UploadResult> {
    const jwtApiKey = await this.getJWTApiKey();
    const formData = new FormData();
    formData.append("file", file, file.name);

    const response = await fetch(
      "https://ipfs-uploader.zora.co/api/v0/add?cid-version=1",
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${jwtApiKey}`,
          Accept: "*/*",
        },
        body: formData,
      },
    );

    if (!response.ok) {
      console.error(await response.text());
      throw new Error(`Failed to upload file: ${response.statusText}`);
    }

    const data = (await response.json()) as {
      cid: string;
      size: number | undefined;
      mimeType: string | undefined;
    };

    return {
      url: `ipfs://${data.cid}`,
      size: data.size,
      mimeType: data.mimeType,
    };
  }
}

/**
 * Create a new Zora IPFS uploader
 */
export function createZoraUploaderForCreator(
  creatorAddress: Address,
): Uploader {
  return new ZoraUploader(creatorAddress);
}
