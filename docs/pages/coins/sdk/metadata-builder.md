# Metadata Builder

The ZORA SDK supports handling metadata when using an SDK API key.

This utilizes ZORA's internal IPFS pinning and delivery infastructure.

You are welcome to implement your own uploader or connect another IPFS provider to the uploader infastructure. You'll get performant uploads and more reliable metadata indexing using this service. You also can utilize a `multiUploader` interface to upload to both your own service and ZORA's service.

## Example Usage

```ts twoslash
import { createMetadataBuilder, createZoraUploaderForCreator } from "@zoralabs/coins-sdk";
import { Address } from "viem";

const creatorAddress = "0x17cd072cBd45031EFc21Da538c783E0ed3b25DCc";

const { createMetadataParameters } = await createMetadataBuilder()
  .withName("Test Base ZORA Coin")
  .withSymbol("TBZC")
  .withDescription("Test Description")
  .withImage(
    new File([/* data for png as bytes or file from user */ ""], "test.png", { type: "image/png" }),
  )
  .upload(createZoraUploaderForCreator(creatorAddress as Address));

// Use this directly with the create coin APIs:
// metadata: createMetadataParameters.metadata
const metadata = createMetadataParameters.metadata;
```

## Metadata Validation

The metadata builder has basic validation for metadata including:

1. Name, symbol, image are required at minimum.
2. URLs cannot be submitted when files are submitted.
3. Either URLs or Files can be submitted for both media and image.
4. Image mime type is restricted to what displays on zora.co.

Errors are fairly specific and emitted as exceptions when using the builder interface usually when calling `validate`.

## Uploader Interface

```ts
/**
 * Result from uploading a file to a storage provider
 */
export type UploadResult = {
  url: string;
  size: number | undefined;
  mimeType: string | undefined;
};

/**
 * Interface for file uploaders (IPFS, Arweave, etc.)
 */
export interface Uploader {
  upload(file: File): Promise<UploadResult>;
}
```

Any uploader supporting this interface can work with this builder pattern.

One key note is only the `url` in the response is required, everything else is optional.
