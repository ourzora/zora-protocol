import { Box, Text } from "ink";
import {
  formatCurrency,
  formatMcapChange,
  formatHolders,
  formatCreatedAt,
} from "../lib/format.js";
import type { ResolvedCoin } from "../lib/coin-ref.js";

const LABEL_WIDTH = 18;

function Row({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <Box>
      <Box width={LABEL_WIDTH} flexShrink={0}>
        <Text dimColor>{label}</Text>
      </Box>
      <Text>{children}</Text>
    </Box>
  );
}

export function CoinDetail({ coin }: { coin: ResolvedCoin }) {
  const change = formatMcapChange(coin.marketCap, coin.marketCapDelta24h);

  return (
    <Box flexDirection="column" paddingLeft={1}>
      <Box marginTop={1} flexDirection="column">
        <Text bold>{coin.name}</Text>
        <Text>
          {coin.coinType} {"\u00b7"} {coin.address}
        </Text>
      </Box>

      <Box marginTop={1} flexDirection="column">
        <Row label="Market Cap">{formatCurrency(coin.marketCap)}</Row>
        <Row label="24h Volume">{formatCurrency(coin.volume24h)}</Row>
        <Row label="24h Change">
          <Text color={change.color}>{change.text}</Text>
        </Row>
        <Row label="Holders">{formatHolders(coin.uniqueHolders)}</Row>
        {coin.coinType === "post" &&
          (coin.creatorHandle ?? coin.creatorAddress) && (
            <Row label="Creator">
              {coin.creatorHandle ?? coin.creatorAddress}
            </Row>
          )}
        <Row label="Created">{formatCreatedAt(coin.createdAt)}</Row>
      </Box>

      <Box marginBottom={1} />
    </Box>
  );
}
