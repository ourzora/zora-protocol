import { Box, Text } from "ink";

const LABEL_WIDTH = 18;

type PriceHistoryProps = {
  coin: string;
  coinType: string;
  interval: string;
  high: string;
  low: string;
  change: { text: string; color: "green" | "red" | undefined };
  sparklineText: string;
};

const Row = ({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) => (
  <Box>
    <Box width={LABEL_WIDTH} flexShrink={0}>
      <Text dimColor>{label}</Text>
    </Box>
    <Text>{children}</Text>
  </Box>
);

const PriceHistory = ({
  coin,
  coinType,
  interval,
  high,
  low,
  change,
  sparklineText,
}: PriceHistoryProps) => (
  <Box flexDirection="column" paddingLeft={1}>
    <Box marginTop={1} flexDirection="column">
      <Row label="Coin">{coin}</Row>
      <Row label="Type">{coinType}</Row>
      <Row label="Interval">{interval}</Row>
      <Row label="High">{high}</Row>
      <Row label="Low">{low}</Row>
      <Row label="Change">
        <Text color={change.color}>{change.text}</Text>
      </Row>
    </Box>

    {sparklineText.length > 0 && (
      <Box marginTop={1} flexDirection="column">
        <Text>{sparklineText}</Text>
      </Box>
    )}

    <Box marginBottom={1} />
  </Box>
);

export { PriceHistory };
export type { PriceHistoryProps };
