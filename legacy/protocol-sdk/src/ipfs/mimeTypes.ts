// text
const HTML = "text/html";
const MARKDOWN = "text/markdown";
const MARKDOWN_UTF8 = "text/markdown; charset=utf-8";
const TEXT_PLAIN_UTF8 = "text/plain; charset=utf-8";
export const TEXT_PLAIN = "text/plain";
const CSV = "text/csv";
const NUMBERS = ".numbers";
const EXCEL = ".xlsx";
const PDF = "application/pdf";

// image
const JPG = "image/jpg";
const JPEG = "image/jpeg";
const PNG = "image/png";
const WEBP = "image/webp";
const SVG = "image/svg+xml";
const TIFF = "image/tiff";
const GIF = "image/gif";

export const isImage = (mimeType: string | null | undefined) => {
  if (!mimeType) return false;
  return [JPG, JPEG, PNG, WEBP, SVG, TIFF, GIF].includes(mimeType);
};

export enum MediaType {
  CSV = "CSV",
  NUMBERS = "NUMBERS",
  EXCEL = "EXCEL",
  IMAGE = "IMAGE",
  VIDEO = "VIDEO",
  AUDIO = "AUDIO",
  TIFF = "TIFF",
  TEXT = "TEXT",
  PDF = "PDF",
  MODEL = "MODEL",
  HTML = "HTML",
  ZIP = "ZIP",
  UNKNOWN = "UNKNOWN",
}

export const DEFAULT_THUMBNAIL_CID_HASHES: { [key: string]: string } = {
  [MediaType.AUDIO]:
    "bafkreidir5laqi26ta6ivnpe2zpekgrfcyi4tb5x6vhwmwnledmzxshfb4",
  [MediaType.VIDEO]:
    "bafkreifm4edadl3j5luoyvw4p6elxeqd77la7bulee6vhq5gq4chfk32mu",
  [MediaType.HTML]:
    "bafkreifgvi6xfwqy2l6g45csyokejpaib52ee7zrw6etrxl2tas4xkkclq",
  [MediaType.ZIP]:
    "bafkreihe5rr5jbkwzegisjlhxbb7jw22xw5oilfmgd2re6tz6buo4pasdq", // assuming all zip files are html directories
  [MediaType.TEXT]:
    "bafkreiaez25nfgggzrnza2loxf6xueb2esm44pnyjyulwoslnipowrf56q",
  default: "bafkreihcoahllisbpb4eeypdwtm7go5uh275wxd7wf2tantpxlpjhviok4",
};

// video
const MP4 = "video/mp4";
const QUICKTIME = "video/quicktime";
const M4V = "video/x-m4v";
const WEBM = "video/webm";

// audio
const M4A = "audio/x-m4a";
const MPEG = "audio/mpeg";
const MP3 = "audio/mp3";
const WAV = "audio/wav";
const VND_WAV = "audio/vnd.wav";
const VND_WAVE = "audio/vnd.wave";
const WAVE = "audio/wave";
const X_WAV = "audio/x-wav";
const AIFF = "audio/aiff";

// 3D
const GLTF = "model/gltf+json";
const GLB = "model/gltf-binary";
// File extensions, as some files return '' as the mimetype
const GLTF_EXT = ".gltf";
const GLB_EXT = ".glb";

// application
export const JSON_MIME_TYPE = "application/json";
const ZIP = "application/zip";

const mimeToMediaType = {
  [HTML]: MediaType.HTML,
  [JPG]: MediaType.IMAGE,
  [JPEG]: MediaType.IMAGE,
  [PNG]: MediaType.IMAGE,
  [WEBP]: MediaType.IMAGE,
  [SVG]: MediaType.IMAGE,
  [TIFF]: MediaType.TIFF,
  [GIF]: MediaType.IMAGE,
  [MP4]: MediaType.VIDEO,
  [WEBM]: MediaType.VIDEO,
  [QUICKTIME]: MediaType.VIDEO,
  [M4V]: MediaType.VIDEO,
  [MPEG]: MediaType.AUDIO,
  [MP3]: MediaType.AUDIO,
  [M4A]: MediaType.AUDIO,
  [VND_WAV]: MediaType.AUDIO,
  [VND_WAVE]: MediaType.AUDIO,
  [WAV]: MediaType.AUDIO,
  [WAVE]: MediaType.AUDIO,
  [X_WAV]: MediaType.AUDIO,
  [AIFF]: MediaType.AUDIO,
  [TEXT_PLAIN]: MediaType.TEXT,
  [TEXT_PLAIN_UTF8]: MediaType.TEXT,
  [MARKDOWN]: MediaType.TEXT,
  [MARKDOWN_UTF8]: MediaType.TEXT,
  [CSV]: MediaType.CSV,
  [NUMBERS]: MediaType.NUMBERS,
  [EXCEL]: MediaType.EXCEL,
  [PDF]: MediaType.PDF,
  [ZIP]: MediaType.ZIP,
  [GLTF]: MediaType.MODEL,
  [GLTF_EXT]: MediaType.MODEL,
  [GLB]: MediaType.MODEL,
  // GLTF returns 'application/json' as the mimetype,
  // and as the only JSON-encoded media we currently support,
  // we assume that if the mimetype is JSON, it's a GLTF
  [JSON_MIME_TYPE]: MediaType.MODEL,
  [GLB_EXT]: MediaType.MODEL,
} as const;

/** Return a MediaType for the given mime type. If mime type is unknown you can provide a filename as a fallback, where the type will be guessed based on extension. */
export function mimeTypeToMedia(mimeType?: string | null) {
  if (!mimeType) return MediaType.UNKNOWN;

  return (
    mimeToMediaType[mimeType as keyof typeof mimeToMediaType] ||
    MediaType.UNKNOWN
  );
}

export async function getMimeType(uri?: string) {
  if (!uri) return uri;

  const res = await fetch(uri, { method: "HEAD" });
  let mimeType = res.headers.get("content-type");
  return mimeType;
}
