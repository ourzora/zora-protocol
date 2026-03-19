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
};

const truncate = (str: string, max: number): string => {
  if (str.length <= max) return str;
  return str.slice(0, max - 1) + "\u2026";
};

const TableComponent = <T,>({
  columns,
  data,
  title,
  subtitle,
}: TableProps<T>) => (
  <Box flexDirection="column" paddingTop={1} paddingBottom={1}>
    {title && (
      <Box paddingLeft={1} marginBottom={1}>
        <Text bold>{title}</Text>
        {subtitle && <Text dimColor> {subtitle}</Text>}
      </Box>
    )}

    <Box paddingLeft={1}>
      {columns.map((col) => (
        <Box key={col.header} width={col.width}>
          <Text bold dimColor>
            {col.header}
          </Text>
        </Box>
      ))}
    </Box>

    {data.map((row, i) => (
      <Box key={i} paddingLeft={1}>
        {columns.map((col) => {
          const value = col.noTruncate
            ? col.accessor(row)
            : truncate(col.accessor(row), col.width - 2);
          const colorName = col.color?.(row);
          return (
            <Box key={col.header} width={col.width}>
              <Text color={colorName}>{value}</Text>
            </Box>
          );
        })}
      </Box>
    ))}
  </Box>
);

export { Column, TableProps, TableComponent, truncate };
