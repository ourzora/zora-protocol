import {
  CreateMetadataParameters,
  Uploader,
  UploadResult,
  ValidMetadataURI,
} from "./types";

type Metadata = {
  name: string;
  symbol: string;
  description: string;
  image: string;
  properties?: Record<string, string>;
  animation_url?: string;
  content?: {
    uri: string;
    mime: string | undefined;
  };
};

export function validateImageMimeType(mimeType: string) {
  if (
    ![
      "image/png",
      "image/jpeg",
      "image/jpg",
      "image/gif",
      "image/svg+xml",
    ].includes(mimeType)
  ) {
    throw new Error("Image must be a PNG, JPEG, JPG, GIF or SVG");
  }
}

export function getURLFromUploadResult(uploadResult: UploadResult) {
  return new URL(uploadResult.url);
}

export class CoinMetadataBuilder {
  private name: string | undefined;
  private description: string | undefined;
  private symbol: string | undefined;
  private imageFile: File | undefined;
  private imageURL: URL | undefined;
  private mediaFile: File | undefined;
  private mediaURL: URL | undefined;
  private mediaMimeType: string | undefined;
  private properties: Record<string, string> | undefined;

  withName(name: string) {
    this.name = name;
    if (typeof name !== "string") {
      throw new Error("Name must be a string");
    }

    return this;
  }

  withSymbol(symbol: string) {
    this.symbol = symbol;
    if (typeof symbol !== "string") {
      throw new Error("Symbol must be a string");
    }

    return this;
  }

  withDescription(description: string) {
    this.description = description;
    if (typeof description !== "string") {
      throw new Error("Description must be a string");
    }

    return this;
  }

  withImage(image: File) {
    if (this.imageURL) {
      throw new Error("Image URL already set");
    }
    if (!(image instanceof File)) {
      throw new Error("Image must be a File");
    }
    validateImageMimeType(image.type);
    this.imageFile = image;

    return this;
  }

  withImageURI(imageURI: string) {
    if (this.imageFile) {
      throw new Error("Image file already set");
    }
    if (typeof imageURI !== "string") {
      throw new Error("Image URI must be a string");
    }
    const url = new URL(imageURI);
    this.imageURL = url;

    return this;
  }

  withProperties(properties: Record<string, string>) {
    for (const [key, value] of Object.entries(properties)) {
      if (typeof key !== "string") {
        throw new Error("Property key must be a string");
      }
      if (typeof value !== "string") {
        throw new Error("Property value must be a string");
      }
    }
    if (!this.properties) {
      this.properties = {};
    }
    this.properties = { ...this.properties, ...properties };

    return this;
  }

  withMedia(media: File) {
    if (this.mediaURL) {
      throw new Error("Media URL already set");
    }
    if (!(media instanceof File)) {
      throw new Error("Media must be a File");
    }
    this.mediaMimeType = media.type;
    this.mediaFile = media;

    return this;
  }

  withMediaURI(mediaURI: string, mediaMimeType: string | undefined) {
    if (this.mediaFile) {
      throw new Error("Media file already set");
    }
    if (typeof mediaURI !== "string") {
      throw new Error("Media URI must be a string");
    }
    const url = new URL(mediaURI);
    this.mediaURL = url;
    this.mediaMimeType = mediaMimeType;

    return this;
  }

  validate() {
    if (!this.name) {
      throw new Error("Name is required");
    }
    if (!this.symbol) {
      throw new Error("Symbol is required");
    }
    if (!this.imageFile && !this.imageURL) {
      throw new Error("Image is required");
    }

    return this;
  }

  generateMetadata(): Metadata {
    return {
      name: this.name!,
      symbol: this.symbol!,
      description: this.description!,
      image: this.imageURL!.toString(),
      animation_url: this.mediaURL?.toString(),
      content: this.mediaURL
        ? {
            uri: this.mediaURL?.toString(),
            mime: this.mediaMimeType,
          }
        : undefined,
      properties: this.properties,
    };
  }

  async upload(uploader: Uploader): Promise<{
    url: ValidMetadataURI;
    createMetadataParameters: CreateMetadataParameters;
    metadata: Metadata;
  }> {
    this.validate();

    if (this.imageFile) {
      const uploadResult = await uploader.upload(this.imageFile);
      this.imageURL = getURLFromUploadResult(uploadResult);
    }
    if (this.mediaFile) {
      const uploadResult = await uploader.upload(this.mediaFile);
      this.mediaURL = getURLFromUploadResult(uploadResult);
    }
    const metadata = this.generateMetadata();
    const uploadResult = await uploader.upload(
      new File([JSON.stringify(metadata)], "metadata.json", {
        type: "application/json",
      }),
    );

    return {
      url: getURLFromUploadResult(uploadResult).toString() as ValidMetadataURI,
      createMetadataParameters: {
        name: this.name!,
        symbol: this.symbol!,
        uri: uploadResult.url as `ipfs://${string}`,
      },
      metadata,
    };
  }
}

export function createMetadataBuilder() {
  return new CoinMetadataBuilder();
}
