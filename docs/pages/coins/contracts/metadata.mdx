# Coins Metadata

Coins follow the [EIP-7572](https://eips.ethereum.org/EIPS/eip-7572) standard for metadata.

This is based off of the `EIP721` and `EIP1155` metadata standards.

We have a guide below for recommended format along with ZORA extensions and validator tools:

## Metadata JSON Format

Your metadata JSON file should follow this format:

```json
{
  "name": "horse",
  "description": "boundless energy",
  "image": "ipfs://bafkreifch6stfh3fn3nqv5tpxnknjpo7zulqav55f2b5pryadx6hldldwe",
  "properties": {
    "category": "social"
  }
}
    ```

Optionally, for non-image assets, the `animation_url` property can be used to link an audio or video file preferably on IPFS.

The `content` property extension is an object that contains the mime type and uri of the asset to help with better indexing and is more consistent than the opensea-specific animation_url field.

```json
{
  "name": "boundless horse",
  "description": "boundless horse",
  "image": "ipfs://bafkreifch6stfh3fn3nqv5tpxnknjpo7zulqav55f2b5pryadx6hldldwe",
  "animation_url": "ipfs://bafybeiatmngyt4wwu6mla27523qk33klxopycomegris3n25y6rcqs27c4",
  "content": {
    "mime": "video/mp4",
    "uri": "ipfs://bafybeiatmngyt4wwu6mla27523qk33klxopycomegris3n25y6rcqs27c4"
  },
  "properties": {
    "category": "social"
  }
}
```

## Metadata JSON Validator

We have a validator that can be used to check your metadata JSON.

The two supported functions are:

- `validateMetadata`
- `validateMetadataURI`

### validateMetadata

This function validates the metadata JSON file.

```ts twoslash
import { validateMetadataJSON } from "@zoralabs/coins-sdk";

validateMetadataJSON({
    name: "horse",
    description: "boundless energy",
    image: 123,
    foo: "bar"
})

```

This function will throw an error if the metadata is invalid and return `true` if it is valid.

### validateMetadataURI

This function validates the metadata URI.

```ts twoslash

function assertTrue(condition: boolean) { }

// ---cut---
import { validateMetadataURIContent } from "@zoralabs/coins-sdk";

assertTrue(await validateMetadataURIContent("https://theme.wtf/metadata/metadata.json"));

// This will throw an error
await validateMetadataURIContent("data:foo");

// This will succeed :)
await validateMetadataURIContent("ipfs://bafybeigoxzqzbnxsn35vq7lls3ljxdcwjafxvbvkivprsodzrptpiguysy");

```

This function will throw an error if the metadata URI is invalid and return `true` if it is valid.



