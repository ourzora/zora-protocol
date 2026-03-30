/**
 * Parse Commander help text into titled sections.
 * Pure function — no dependencies on Ink or React.
 */
const DEFAULT_DESC_COLUMN = 38;
// Regex match groups: [1] label (e.g. command name), [2] separator (2+ spaces/tabs), [3] description
export const TWO_COLUMN_REGEX = /^(.+\S)([ \t]{2,})(\S.*)/m;

/**
 * Find the character offset where the description column starts
 * in Commander's two-column help output (e.g., command names on the left,
 * descriptions on the right). Returns a default of 38 if not detected.
 */
export function getDescriptionColumnOffset(
  sections: { title: string; content: string }[],
): number {
  for (const section of sections) {
    const match = section.content.match(TWO_COLUMN_REGEX);
    if (match) {
      return match[1].length + match[2].length;
    }
  }
  return DEFAULT_DESC_COLUMN;
}

export function parseHelpSections(
  text: string,
): { title: string; content: string }[] {
  const sections: { title: string; content: string }[] = [];
  let currentTitle = "";
  let currentLines: string[] = [];

  for (const line of text.split("\n")) {
    const match = line.match(/^([A-Z]\w+):(.*)/);
    if (match) {
      if (currentTitle) {
        const content = currentLines.join("\n").replace(/^\n+|\n+$/g, "");
        sections.push({ title: currentTitle, content });
      }
      currentTitle = match[1];
      currentLines = match[2].trim() ? [match[2].trim()] : [];
    } else if (currentTitle) {
      // Strip common 2-space Commander indent
      currentLines.push(line.startsWith("  ") ? line.slice(2) : line);
    }
  }

  if (currentTitle) {
    const content = currentLines.join("\n").replace(/^\n+|\n+$/g, "");
    sections.push({ title: currentTitle, content });
  }

  return sections.filter((s) => s.content);
}
