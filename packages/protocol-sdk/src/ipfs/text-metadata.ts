import { TextMetadataFiles } from "./types";

const CHAR_LIMIT = 1111;

const wrapText = ({
  ctx,
  text,
  x,
  y,
  maxWidth,
  lineHeight,
}: {
  ctx: CanvasRenderingContext2D;
  text: string;
  x: number;
  y: number;
  maxWidth: number;
  lineHeight: number;
}) => {
  // Split text into words
  let words = text.replaceAll("\n", " \n ").split(/ +/);
  let line = ""; // This will store the text of the current line
  let testLine = ""; // This will store the text when we add a word, to test if it's too long
  let lineArray = []; // This is an array of lines, which the function will return

  for (var n = 0; n < words.length; n++) {
    // Measure text sizing
    testLine += `${words[n]} `;
    let metrics = ctx.measureText(testLine);
    let testWidth = metrics.width;
    // If the width of this test line is more than the max width
    if (words[n]?.includes("\n") || (testWidth > maxWidth && n > 0)) {
      // Then the line is finished, push the current line into "lineArray"
      lineArray.push({ text: line, x, y });
      // Start a new line
      y += lineHeight;
      // Update line and test line to use this word as the first word on the next line
      // If it's a newline, then don't add a space
      if (words[n]?.includes("\n")) {
        line = ``;
        testLine = ``;
      } else {
        line = `${words[n]} `;
        testLine = `${words[n]} `;
      }
    } else {
      // Test line is less than the max width, add the word to the current line
      line += `${words[n]} `;
    }
    // Handle a single line...
    if (n === words.length - 1) {
      lineArray.push({ text: line, x, y });
    }
  }
  return lineArray;
};

async function generateTextPreview(text: string): Promise<File> {
  // Trim the text to a reasonable max length. Prevent crashes if the user pastes a gigantic string
  const trimmedText = text.trim().slice(0, CHAR_LIMIT);

  const [width, height] = [500, 500];
  const padding = 20;
  const dpr = 2;

  const fontFamily = "Inter";
  const [fontSize, lineHeight] = [16, 24];
  const [textColor, backgroundColor] = ["black", "white"];

  return new Promise((resolve, reject) => {
    const canvas = document.createElement("canvas");
    canvas.width = width * dpr;
    canvas.height = height * dpr;
    const ctx = canvas.getContext("2d");
    if (!ctx) {
      return reject(new Error("Could not create canvas context"));
    }
    ctx.fillStyle = backgroundColor;
    ctx.fillRect(0, 0, width * dpr, width * dpr);
    ctx.fillStyle = textColor;
    ctx.font = `${fontSize * dpr}px ${fontFamily}`;
    const wrapped = wrapText({
      ctx,
      text: trimmedText,
      x: padding * dpr,
      y: fontSize * dpr + padding * dpr,
      maxWidth: width * dpr - padding * 2 * dpr,
      lineHeight: lineHeight * dpr,
    });
    wrapped.forEach((line) => ctx.fillText(line.text, line.x, line.y));
    canvas.toBlob((blob) => {
      if (!blob) {
        return reject(new Error("Could not create blob"));
      }
      resolve(new File([blob], "thumbnail.png", { type: "image/png" }));
    });
  });
}

function generateTextTitle(text: string) {
  const firstLine = text.split("\n")[0]!;
  const firstSentence = firstLine?.split(". ")[0]!;

  if (firstSentence.length > 50) {
    return firstSentence.slice(0, 50) + "...";
  }

  return firstSentence;
}

const toTextFile = (text: string) =>
  new File([text], "Untitled.txt", { type: "text/plain" });

/** For text nfts, this will generate files that are needed for the metadata json, including the txt.file containing the text, and a thumbnail image containing a preview of the text
 */
export async function generateTextNftMetadataFiles(
  text: string,
): Promise<TextMetadataFiles> {
  const name = generateTextTitle(text);
  const textFile = toTextFile(text);
  const thumbnailFile = await generateTextPreview(text);

  return {
    name,
    mediaUrlFile: textFile,
    thumbnailFile,
  };
}
