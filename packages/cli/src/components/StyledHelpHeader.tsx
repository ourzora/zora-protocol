import { Text, Box } from "ink";
import { Zorb } from "./Zorb.js";
import { getDescriptionColumnOffset } from "../lib/parse-help.js";

export function StyledHelpHeader({
  sections,
}: {
  sections: { title: string; content: string }[];
}) {
  const descriptionColumnOffset = getDescriptionColumnOffset(sections);
  return (
    <Box
      flexDirection="row"
      borderStyle="single"
      borderDimColor
      paddingX={1}
      paddingY={1}
    >
      <Box flexShrink={0} width={descriptionColumnOffset}>
        <Zorb size={20} />
      </Box>
      <Box flexDirection="column" flexGrow={1} justifyContent="center">
        <Text bold>Zora CLI</Text>
      </Box>
    </Box>
  );
}
