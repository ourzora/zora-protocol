import React from "react";
import { Composition } from "remotion";
import { TerminalDemo } from "./TerminalDemo";

export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="TerminalDemo"
      component={TerminalDemo}
      durationInFrames={315}
      fps={30}
      width={622}
      height={356}
    />
  );
};
