# Preserved failed source-only agent dispatch

The parallel subagent invocation returned asynchronously, then both jobs failed before starting: `Unknown agent: "nr-source-only". Available agents: none.` No analyst or model work ran.

Main checked installed subagent/index.ts: discovery uses `discoverAgents(ctx.cwd, agentScope)` (line587), not per-task cwd. This Main session cwd is /home/user, so the new definition confined under reviews is not discoverable through that tool despite each task's correct isolated cwd. No global agent definition/settings were changed to bypass the reviews-only write scope. Do not repeat the same invocation or describe these agents as active.

Source packets and candidate local definition are retained. Main continues bottleneck host/shape recovery directly; no user confirmation is needed. Tool allowlist design was read/write/edit with no shell, but it never reached process launch and must not be claimed as an active sandbox.
