const BLOCKS = "▁▂▃▄▅▆▇█";

const sparkline = (values: number[]): string => {
  if (values.length <= 1) return values.length === 1 ? BLOCKS[4] : "";

  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = max - min;

  if (range === 0) return BLOCKS[4].repeat(values.length);

  return values
    .map((v) => {
      const idx = Math.round(((v - min) / range) * (BLOCKS.length - 1));
      return BLOCKS[idx];
    })
    .join("");
};

const MAX_SPARKLINE_WIDTH = 50;

const downsample = (values: number[], maxWidth: number): number[] => {
  if (values.length <= maxWidth) return values;

  const bucketSize = values.length / maxWidth;
  const result: number[] = [];

  for (let i = 0; i < maxWidth; i++) {
    const start = Math.floor(i * bucketSize);
    const end = Math.floor((i + 1) * bucketSize);
    let sum = 0;
    for (let j = start; j < end; j++) {
      sum += values[j];
    }
    result.push(sum / (end - start));
  }

  return result;
};

export { sparkline, downsample, MAX_SPARKLINE_WIDTH };
