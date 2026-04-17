import { Box, Text } from "ink";

type Column<T> = {
  header: string;
  width: number;
  accessor: (row: T) => string;
  color?: (row: T) => string | undefined;
  noTruncate?: boolean;
};

type TableProps<T> = {
  columns: Column<T>[];
  data: T[];
  title?: string;
  subtitle?: string;
  fullWidth?: boolean;
  footer?: string;
  selectedRow?: number;
};

const PADDING_LEFT = 1;

const truncate = (str: string, max: number): string => {
  if (str.length <= max) return str;
  return str.slice(0, max - 1) + "\u2026";
};

const computeColumnWidths = <T,>(
  columns: Column<T>[],
  fullWidth: boolean,
): number[] => {
  const baseWidths = columns.map((col) => col.width);
  const totalBase = baseWidths.reduce((sum, w) => sum + w, 0);

  if (!fullWidth) return baseWidths;

  const width = process.stdout.columns ?? 80;
  const available = width - PADDING_LEFT;

  if (available <= totalBase) return baseWidths;

  const computed = baseWidths.map((w) =>
    Math.max(1, Math.floor((w / totalBase) * available)),
  );
  let remainder = available - computed.reduce((sum, w) => sum + w, 0);

  for (let i = 0; i < computed.length && remainder > 0; i++) {
    computed[i]++;
    remainder--;
  }

  return computed;
};

const Table = <T,>({
  columns,
  data,
  title,
  subtitle,
  fullWidth = true,
  footer,
  selectedRow,
}: TableProps<T>) => {
  const widths = computeColumnWidths(columns, fullWidth);

  return (
    <Box flexDirection="column" paddingTop={1} paddingBottom={1}>
      {title && (
        <Box paddingLeft={PADDING_LEFT} marginBottom={1}>
          <Text bold>{title}</Text>
          {subtitle && <Text dimColor> {subtitle}</Text>}
        </Box>
      )}

      <Box paddingLeft={PADDING_LEFT}>
        {columns.map((col, i) => (
          <Box key={col.header} width={widths[i]}>
            <Text bold dimColor wrap="truncate">
              {col.header}
            </Text>
          </Box>
        ))}
      </Box>

      {data.map((row, i) => {
        const isSelected = selectedRow === i;
        return (
          <Box key={i} paddingLeft={PADDING_LEFT}>
            {columns.map((col, colIdx) => {
              const colWidth = widths[colIdx];
              const value = col.noTruncate
                ? col.accessor(row)
                : truncate(col.accessor(row), colWidth - 2);
              const colorName = col.color?.(row);
              return (
                <Box key={col.header} width={colWidth}>
                  <Text
                    color={colorName}
                    bold={isSelected}
                    inverse={isSelected}
                    wrap={col.noTruncate ? "wrap" : "truncate"}
                  >
                    {value}
                  </Text>
                </Box>
              );
            })}
          </Box>
        );
      })}

      {footer && (
        <Box paddingLeft={PADDING_LEFT} marginTop={1}>
          <Text dimColor wrap="wrap">
            {footer}
          </Text>
        </Box>
      )}
    </Box>
  );
};

export { Column, TableProps, Table, truncate, computeColumnWidths };
