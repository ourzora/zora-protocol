import type { ReactElement } from "react";
import { render } from "ink";

const renderOnce = (element: ReactElement): void => {
  const { unmount } = render(element);
  // Ink renders synchronously for static content, unmount immediately
  unmount();
};

export { renderOnce };
