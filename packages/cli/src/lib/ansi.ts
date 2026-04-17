export const DIM = "\x1b[2m";
export const BOLD = "\x1b[1m";
export const YELLOW = "\x1b[33m";
export const RESET = "\x1b[0m";
export const useAnsi = () => process.stdout.isTTY && !process.env.NO_COLOR;
