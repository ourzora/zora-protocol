import { Address } from "viem";
import { Uploader, UploadOptions, UploadResult } from "../types";
import { getApiKey } from "../../api/api-key";
import { setCreateUploadJwt } from "../../api/internal";

const JWT_TTL_MS = 1000 * 60 * 60; // 1 hour
const JWT_FETCH_TIMEOUT_MS = 15_000; // 15 seconds

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

  private invalidateJwt() {
    this.jwtApiKey = undefined;
    this.jwtApiKeyExpiresAt = undefined;
  }

  private async getJWTApiKey(signal?: AbortSignal) {
    if (
      this.jwtApiKey &&
      this.jwtApiKeyExpiresAt &&
      this.jwtApiKeyExpiresAt > Date.now()
    ) {
      return this.jwtApiKey;
    }

    const jwtSignal = AbortSignal.timeout(JWT_FETCH_TIMEOUT_MS);
    const combinedSignal = signal
      ? AbortSignal.any([signal, jwtSignal])
      : jwtSignal;

    const response = await setCreateUploadJwt(
      {
        creatorAddress: this.creatorAddress,
      },
      { signal: combinedSignal },
    );
    this.jwtApiKey = response.data?.createUploadJwtFromApiKey;
    if (!this.jwtApiKey) {
      throw new Error("Failed to create upload JWT");
    }

    this.jwtApiKeyExpiresAt = Date.now() + JWT_TTL_MS;

    return this.jwtApiKey;
  }

  private buildUploadSignal(options?: UploadOptions): AbortSignal | undefined {
    const { signal, timeout } = options ?? {};
    if (signal && timeout) {
      return AbortSignal.any([signal, AbortSignal.timeout(timeout)]);
    }
    if (timeout) {
      return AbortSignal.timeout(timeout);
    }
    return signal;
  }

  private async doUpload(
    file: File,
    jwt: string,
    signal?: AbortSignal,
  ): Promise<Response> {
    const formData = new FormData();
    formData.append("file", file, file.name);

    return fetch("https://ipfs-uploader.zora.co/api/v0/add?cid-version=1", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${jwt}`,
        Accept: "*/*",
      },
      body: formData,
      signal,
    });
  }

  async upload(file: File, options?: UploadOptions): Promise<UploadResult> {
    const uploadSignal = this.buildUploadSignal(options);

    const jwt = await this.getJWTApiKey(uploadSignal);
    let response = await this.doUpload(file, jwt, uploadSignal);

    // On 401, refresh the JWT exactly once and retry
    if (response.status === 401) {
      this.invalidateJwt();
      const freshJwt = await this.getJWTApiKey(uploadSignal);
      response = await this.doUpload(file, freshJwt, uploadSignal);
    }

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
