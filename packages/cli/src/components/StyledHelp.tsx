import type { ReactNode } from "react";
import { Text, Box } from "ink";
import { KeyValueTable, type KeyValueRow } from "./KeyValueTable.js";
import {
  getDescriptionColumnOffset,
  TWO_COLUMN_REGEX,
} from "../lib/parse-help.js";

/**
 * Render parsed Commander help sections as bordered boxes
 * with bold labels and dim values.
 */
export function StyledHelp({
  sections,
  header,
}: {
  sections: { title: string; content: string }[];
  header?: ReactNode;
}) {
  const descriptionColumnOffset = getDescriptionColumnOffset(sections);

  return (
    <Box flexDirection="column" gap={1}>
      {header}
      {sections.map((section, i) => {
        const hasTwoColumns = TWO_COLUMN_REGEX.test(section.content);
        const rows: KeyValueRow[] | null = hasTwoColumns
          ? section.content.split("\n").map((line) => {
              const m = line.match(TWO_COLUMN_REGEX);
              if (m)
                return {
                  label: m[1],
                  value: m[3][0].toUpperCase() + m[3].slice(1),
                };
              return { label: "", value: line.trimStart() };
            })
          : null;
        return (
          <Box
            key={i}
            flexDirection="column"
            borderStyle="single"
            borderDimColor
            paddingX={1}
            paddingY={1}
          >
            <Text bold>
              {section.title}
            </Text>
            {rows ? (
              <KeyValueTable rows={rows} labelWidth={descriptionColumnOffset} />
            ) : (
              <Text>{section.content}</Text>
            )}
          </Box>
        );
      })}
    </Box>
  );
}
