import { YELLOW, RESET, useAnsi } from "./ansi.js";

export function warningBox(text: string) {
  if (!useAnsi()) {
    console.log(`\u26a0  ${text}\n`);
    return;
  }
  console.log(`${YELLOW}\u26a0  ${text}${RESET}\n`);
}
