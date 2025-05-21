import { globalStyle, style } from "@vanilla-extract/css";

export const root = style({});

export const logoDark = style({}, "logoDark");
globalStyle(`:root:not(.dark) ${logoDark}`, {
  display: "none",
});

export const logoLight = style({}, "logoLight");
globalStyle(`:root.dark ${logoLight}`, {
  display: "none",
});

const viewportVars = {
  "max-480px": "screen and (max-width: 480px)",
  "min-480px": "screen and (min-width: 481px)",
  "max-720px": "screen and (max-width: 720px)",
  "min-720px": "screen and (min-width: 721px)",
  "max-1080px": "screen and (max-width: 1080px)",
  "min-1080px": "screen and (min-width: 1081px)",
  "max-1280px": "screen and (max-width: 1280px)",
  "min-1280px": "screen and (min-width: 1281px)",
};

export const logo = style(
  {
    display: "flex",
    justifyContent: "center",
    height: "48px",
    "@media": {
      [viewportVars["max-720px"]]: {
        height: "36px",
      },
    },
  },
  "logo",
);
