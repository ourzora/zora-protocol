import { existsSync } from "node:fs";
import { dirname, join } from "node:path";

export type AgentHarness =
  | "claude"
  | "cursor"
  | "windsurf"
  | "openclaw"
  | "hermes";

export type UapiAgentHarness =
  | "CLAUDE"
  | "CURSOR"
  | "WINDSURF"
  | "OPENCLAW"
  | "HERMES";

export const AGENT_HARNESS_ORDER: AgentHarness[] = [
  "hermes",
  "openclaw",
  "windsurf",
  "claude",
  "cursor",
];

export const AGENT_HARNESS_SKILLS_DIRS: Record<AgentHarness, string> = {
  claude: ".claude/skills",
  cursor: ".cursor/skills",
  windsurf: ".windsurf/skills",
  openclaw: ".openclaw/skills",
  hermes: ".hermes/skills",
};

export const AGENT_HARNESS_ROOT_DIRS: Record<AgentHarness, string> = {
  claude: ".claude",
  cursor: ".cursor",
  windsurf: ".windsurf",
  openclaw: ".openclaw",
  hermes: ".hermes",
};

export const AGENT_HARNESS_TO_UAPI: Record<AgentHarness, UapiAgentHarness> = {
  claude: "CLAUDE",
  cursor: "CURSOR",
  windsurf: "WINDSURF",
  openclaw: "OPENCLAW",
  hermes: "HERMES",
};

export const detectAgentHarnessInDir = (dir: string) =>
  AGENT_HARNESS_ORDER.find((agent) =>
    existsSync(join(dir, AGENT_HARNESS_ROOT_DIRS[agent])),
  );

export const detectAgentHarness = (cwd: string): AgentHarness | undefined => {
  let dir = cwd;

  while (true) {
    const detected = detectAgentHarnessInDir(dir);
    if (detected) return detected;

    const parent = dirname(dir);
    if (parent === dir) return undefined;
    dir = parent;
  }
};

export const mapAgentHarnessToUapi = (
  harness: AgentHarness,
): UapiAgentHarness => AGENT_HARNESS_TO_UAPI[harness];
