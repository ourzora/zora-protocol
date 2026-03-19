import type { ReactElement } from "react";
import { renderToString } from "ink";

const renderOnce = (element: ReactElement): void => {
  const output = renderToString(element);
  console.log(output);
};

export { renderOnce };
