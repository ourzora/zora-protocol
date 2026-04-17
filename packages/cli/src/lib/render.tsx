import type { ReactElement } from "react";
import { render, renderToString } from "ink";

const renderOnce = (element: ReactElement): void => {
  const columns = process.stdout.columns || 80;
  const output = renderToString(element, { columns });
  console.log(output);
};

const renderLive = async (element: ReactElement): Promise<void> => {
  const instance = render(element);
  await instance.waitUntilExit();
};

export { renderOnce, renderLive };
