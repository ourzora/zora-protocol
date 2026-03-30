import { Text, Box } from "ink";

export type KeyValueRow = { label: string; value: string };

/**
 * Two-column table with bold labels and dim values.
 * Pass labelWidth to fix the label column width, or let it auto-size.
 */
export function KeyValueTable({
  rows,
  labelWidth,
}: {
  rows: KeyValueRow[];
  labelWidth?: number;
}) {
  const pad = labelWidth ?? (Math.max(0, ...rows.map((r) => r.label.length)) + 2);
  return (
    <Box flexDirection="column">
      {rows.map((row, i) => (
        <Text key={i}>
          <Text bold>{row.label.padEnd(pad)}</Text>
          <Text dimColor>{row.value}</Text>
        </Text>
      ))}
    </Box>
  );
}
