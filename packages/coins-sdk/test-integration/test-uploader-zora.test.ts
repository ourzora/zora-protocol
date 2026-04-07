import { setApiKey } from "../src/api/api-key";
import { createMetadataBuilder } from "../src/uploader/metadata";
import {
  createZoraUploaderForCreator,
  ZoraUploader,
} from "../src/uploader/providers/zora";
import { describe, expect, it } from "vitest";

describe("Uploader", () => {
  it("should upload an image", async () => {
    setApiKey(process.env.VITE_ZORA_API_KEY!);
    const uploader = new ZoraUploader(
      "0x9444390c01Dd5b7249E53FAc31290F7dFF53450D",
    );
    const result = await uploader.upload(
      new File(
        [
          `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
                <circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red" />
            </svg>`,
        ],
        "test.svg",
        { type: "image/svg+xml" },
      ),
    );
    expect(result).toMatchObject({
      url: "ipfs://bafybeiguslukdujd22p7ix53rcszgbg4ine464g33zk2st3lnjpx4uvmri",
      size: 240,
      mimeType: undefined,
    });
  });
  it("should upload an image and build metadata", async () => {
    setApiKey(process.env.VITE_ZORA_API_KEY!);

    const fileContent = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
                        <circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red" />
                    </svg>`;

    const uploader = createZoraUploaderForCreator(
      "0x9444390c01Dd5b7249E53FAc31290F7dFF53450D",
    );

    const { url, metadata } = await createMetadataBuilder()
      .withName("Test Coin")
      .withSymbol("TEST")
      .withDescription("Test Description")
      .withImage(new File([fileContent], "test.svg", { type: "image/svg+xml" }))
      .upload(uploader);

    expect(metadata).toMatchObject({
      name: "Test Coin",
      symbol: "TEST",
      description: "Test Description",
      image:
        "ipfs://bafybeid24m5qqlfrtpeyxrff6gix7peunh75markjx2a3bm3k3ciyluutm",
    });
    expect(url).toBeInstanceOf(URL);
    expect(url.toString()).toEqual(
      "ipfs://bafybeiefusbl3xprlxc3zn57my6abbrnjk7oa7rv45l67ohfzkioismkqi",
    );
  });
});
