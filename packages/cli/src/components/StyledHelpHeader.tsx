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
        <Text bold>
          <Text backgroundColor="#3fff00" color="black">
            {" "}
            Zora CLI{" "}
          </Text>
        </Text>
        <Text>
          <Text dimColor>Trade what's trending. Run</Text>{" "}
          <Text backgroundColor="#3fff00" color="black">
            {" "}
            zora setup{" "}
          </Text>{" "}
          <Text dimColor>to get started.</Text>
        </Text>
      </Box>
    </Box>
  );
}
