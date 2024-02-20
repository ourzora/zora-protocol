import {
  Bytes,
  JSONValueKind,
  dataSource,
  json,
} from "@graphprotocol/graph-ts";
import { MetadataInfo } from "../../generated/schema";

export function handleJSONMetadataFetched(content: Bytes): void {
  const metadata = new MetadataInfo(dataSource.stringParam());
  metadata.rawJson = content.toString();
  const jsonType = json.try_fromBytes(content);
  if (
    jsonType.isOk &&
    !jsonType.value.isNull() &&
    jsonType.value.kind === JSONValueKind.OBJECT
  ) {
    const value = jsonType.value.toObject();
    if (value) {
      const name = value.get("name");
      if (name && name.kind === JSONValueKind.STRING) {
        metadata.name = name.toString();
      }
      const description = value.get("description");
      if (description && description.kind === JSONValueKind.STRING) {
        metadata.description = description.toString();
      }
      const image = value.get("image");
      if (image && image.kind === JSONValueKind.STRING) {
        metadata.image = image.toString();
      }
      const decimals = value.get("decimals");
      if (
        decimals &&
        (decimals.kind === JSONValueKind.STRING ||
          decimals.kind === JSONValueKind.NUMBER)
      ) {
        metadata.decimals = decimals.toString();
      }
      const animation_url = value.get("animation_url");
      if (animation_url && animation_url.kind === JSONValueKind.STRING) {
        metadata.animationUrl = animation_url.toString();
      }
    }
  }

  metadata.save();
}
