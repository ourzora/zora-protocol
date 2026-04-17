import type { ReactElement } from "react";
import { Text, Box } from "ink";
import {
  generateZorbPixels,
  supportsTruecolor,
  type RGB,
} from "../lib/zorb-pixels.js";

const LOWER_HALF_BLOCK = "\u2584"; // ▄
const UPPER_HALF_BLOCK = "\u2580"; // ▀

function rgbString([r, g, b]: RGB): string {
  return `rgb(${r},${g},${b})`;
}

function isBlack([r, g, b]: RGB): boolean {
  return r === 0 && g === 0 && b === 0;
}

/**
 * Renders the Zora zorb as a truecolor gradient sphere.
 * Uses the half-block technique: each character cell encodes 2 vertical pixels.
 * Top pixel → backgroundColor, bottom pixel → color, character → ▄
 *
 * Returns null if the terminal doesn't support truecolor.
 */
export function Zorb({ size = 20 }: { size?: number }) {
  if (!supportsTruecolor()) return null;

  const grid = generateZorbPixels(size);
  const rows: ReactElement[] = [];

  // Process two rows of pixels at a time
  for (let y = 0; y < size; y += 2) {
    const topRow = grid[y];
    const bottomRow = y + 1 < size ? grid[y + 1] : undefined;
    const cells: ReactElement[] = [];

    for (let x = 0; x < size; x++) {
      const top = topRow[x];
      const bottom = bottomRow ? bottomRow[x] : ([0, 0, 0] as RGB);
      const topIsBlack = isBlack(top);
      const bottomIsBlack = isBlack(bottom);

      if (topIsBlack && bottomIsBlack) {
        cells.push(<Text key={x}> </Text>);
      } else if (topIsBlack) {
        cells.push(
          <Text key={x} color={rgbString(bottom)}>
            {LOWER_HALF_BLOCK}
          </Text>,
        );
      } else if (bottomIsBlack) {
        cells.push(
          <Text key={x} color={rgbString(top)}>
            {UPPER_HALF_BLOCK}
          </Text>,
        );
      } else {
        cells.push(
          <Text
            key={x}
            backgroundColor={rgbString(top)}
            color={rgbString(bottom)}
          >
            {LOWER_HALF_BLOCK}
          </Text>,
        );
      }
    }

    // Wrap cells in <Text> so they render inline (not as flex items)
    rows.push(<Text key={y}>{cells}</Text>);
  }

  return (
    <Box flexDirection="column">
      <Text> </Text>
      {rows}
      <Text> </Text>
    </Box>
  );
}
