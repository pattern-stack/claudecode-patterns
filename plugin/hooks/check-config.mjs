#!/usr/bin/env node
// check-config.mjs — UserPromptSubmit hook surfacing /sdlc:setup when sdlc.yml is missing.
//
// Returns a system-reminder block to the assistant on missing .claude/sdlc.yml,
// nudging it to suggest /sdlc:setup. Quiet otherwise. Wired into plugin.json
// components.hooks.UserPromptSubmit.
//
// Hook protocol: write JSON to stdout. Schema:
//   { "hookSpecificOutput": { "hookEventName": "UserPromptSubmit", "additionalContext": "..." } }
// The additionalContext string is delivered to the assistant as a system reminder.
// (See Claude Code hooks reference for full schema.)

import { existsSync } from "node:fs";
import { join } from "node:path";

const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const sdlcPath = join(projectDir, ".claude", "sdlc.yml");

if (existsSync(sdlcPath)) {
  // Configured project — quiet.
  process.exit(0);
}

const reminder = `The sdlc plugin is installed but this project has no \`.claude/sdlc.yml\` configuration. The SDLC workflow commands (\`/sdlc:plan\`, \`/sdlc:design\`, \`/sdlc:develop\`, \`/sdlc:orchestrate\`, \`/sdlc:sync-issues\`, \`/sdlc:canvas\`) require it.

Suggest the user run \`/sdlc:setup\` to scaffold the config interactively (4 questions: language, quality_profile, task_management, team_key). The setup command also wires the project's Justfile to the plugin's recipes and creates the \`.claude/sdlc.justfile\` symlink.

If the user is intentionally not using SDLC commands in this project (e.g. just using the plugin's skills/canvases), they can ignore this reminder — it appears once per prompt while \`.claude/sdlc.yml\` is absent and is silenced after \`/sdlc:setup\` completes.`;

const output = {
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: reminder,
  },
};

process.stdout.write(JSON.stringify(output));
process.exit(0);
