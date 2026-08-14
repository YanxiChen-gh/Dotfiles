// Dotfiles harness ported to oh-my-pi (omp).
//
// This is the omp equivalent of opencode/plugins/dotfiles-harness.js. It keeps
// only the capabilities that omp does NOT already provide first-party:
//   - scope / verify / PR-authoring gates (shared agent-maturity + claude/hooks scripts)
//   - the comment self-check reminder after edits
//   - Slack attention notifications
//
// Everything the opencode plugin had to reconstruct by hand is gone here:
//   - Herdr subagent/state sync         -> `herdr integration install omp` (native)
//   - Herdr task workspace titles       -> this extension mirrors the OpenCode policy
//   - session-lineage hydration/walk     -> omp tracks sessions natively
//   - event/notification queue plumbing  -> omp lifecycle events are ordered + typed
//   - same-session checkpoint automation -> omp has native auto-compaction
//   - canary takeover                     -> deferred (maturity-flow coupled; see omp/README.md)
//
// omp runs as a single Bun process and does NOT sandbox extensions, so we shell
// out with Bun.spawn exactly like the opencode plugin did - the gate scripts and
// their stdin/exit-code contract are unchanged.

import { realpath } from "node:fs/promises"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

// omp's public extension type. Runtime is Bun, so Bun.* is available at runtime;
// the import is type-only so a plain `bun`/`tsc` check does not need omp installed.
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent"

type HookResult = { stdout: string; stderr: string; exitCode: number; failed: boolean }
type TitleSyncContext = {
  mode: "tui" | "rpc" | "json" | "print"
  sessionManager: { getSessionName(): string | undefined }
  setInterval(callback: () => void | Promise<void>, ms?: number): unknown
}
type HerdrTitleTarget = { kind: "workspace" | "tab"; id: string }

const runHook = async (script: string, payload: unknown, extraEnv: Record<string, string> = {}): Promise<HookResult> => {
  try {
    const proc = Bun.spawn(["bash", script], {
      env: { ...Bun.env, ...extraEnv },
      stdin: new Blob([JSON.stringify(payload)]),
      stdout: "pipe",
      stderr: "pipe",
    })
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
      proc.exited,
    ])
    if (exitCode !== 0 && exitCode !== 2) {
      console.warn(`[dotfiles-harness] hook exited ${exitCode}: ${stderr.trim()}`)
    }
    return { stdout, stderr, exitCode, failed: false }
  } catch (error) {
    // Fail open: a broken hook must never wedge the agent.
    console.warn(`[dotfiles-harness] hook failed open: ${error}`)
    return { stdout: "", stderr: "", exitCode: 0, failed: true }
  }
}

const stringField = (input: Record<string, unknown> | undefined, ...names: string[]): string => {
  for (const name of names) {
    const value = input?.[name]
    if (typeof value === "string") return value
  }
  return ""
}

const slackText = (value: unknown, maxLength = 160): string => {
  if (typeof value !== "string") return ""
  return value
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLength)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/([\\*_~`])/g, "\\$1")
}

const createSlackSender = (home: string) => {
  const executable = Bun.env.SLACK_NOTIFY_BIN ?? join(home, ".local/bin/slack-webhook-post.sh")
  return (message: string) => {
    if (Bun.env.AGENT_SLACK_NOTIFICATIONS === "0") return
    try {
      const proc = Bun.spawn([executable, "default", "-"], {
        env: Bun.env,
        stdin: new Blob([message]),
        stdout: "ignore",
        stderr: "ignore",
      })
      void proc.exited.catch(() => console.warn("[dotfiles-harness] Slack notification failed"))
    } catch {
      console.warn("[dotfiles-harness] Slack notification failed")
    }
  }
}

const invokesLavish = (command: string) => /\b(?:lavish-axi(?:-safe)?|open-lavish)\b/.test(command)

const lavishPollGuidance =
  "In an interactive omp TUI, run each `lavish-axi-safe poll <file>` as one managed Bash job with `async: true`. " +
  "When feedback is delivered, process it and start the next async poll. Do not use a question or approval popup, Hub process, or detached shell."

const shellCommand = (input: Record<string, unknown>): string => {
  const command = stringField(input, "command")
  const application = stringField(input, "application")
  const args = Array.isArray(input.args) ? input.args.filter((value): value is string => typeof value === "string") : []
  return [command, application, ...args].filter(Boolean).join(" ")
}

export default async function dotfilesHarness(pi: ExtensionAPI) {
  const source = await realpath(fileURLToPath(import.meta.url))
  // .../omp/agent/extensions/dotfiles-harness.ts -> extensions -> agent -> omp -> dotfiles
  const dotfiles = dirname(dirname(dirname(dirname(source))))
  const home = Bun.env.HOME ?? ""
  const hooks = join(dotfiles, "claude/hooks")
  const maturity = Bun.env.AGENT_MATURITY_HOME ?? join(home, "agent-maturity")
  const scopePrompt = join(maturity, "scripts/scope-gate-userpromptsubmit.sh")
  const scopeGate = join(maturity, "scripts/scope-gate-pretooluse.sh")
  const notify = createSlackSender(home)
  const workspaceId = Bun.env.HERDR_WORKSPACE_ID
  const tabId = Bun.env.HERDR_TAB_ID
  const herdrTarget: HerdrTitleTarget | undefined =
    Bun.env.HERDR_ENV !== "1"
      ? undefined
      : Bun.env.DOTFILES_HERDR_TASK_WORKSPACE === "1" && workspaceId
        ? { kind: "workspace", id: workspaceId }
        : tabId
          ? { kind: "tab", id: tabId }
          : undefined
  const herdr = Bun.env.HERDR_BIN_PATH ?? "herdr"
  let appliedHerdrTitle = ""
  let herdrTitleSyncInFlight = false
  let activeTitleContext: TitleSyncContext | undefined
  let titleSyncStarted = false

  pi.setLabel("Dotfiles harness")

  const editTools = new Set(["edit", "write", "apply_patch", "str_replace_editor", "str_replace"])
  const shellTools = new Set(["bash", "shell"])

  const syncHerdrTitle = async (ctx: TitleSyncContext): Promise<boolean> => {
    if (!herdrTarget) return true
    const title = ctx.sessionManager.getSessionName()?.trim()
    if (!title || title === appliedHerdrTitle) return Boolean(title)
    if (herdrTitleSyncInFlight) return false

    herdrTitleSyncInFlight = true
    try {
      const proc = Bun.spawn([herdr, herdrTarget.kind, "rename", herdrTarget.id, title], {
        env: Bun.env,
        stdin: "ignore",
        stdout: "ignore",
        stderr: "pipe",
      })
      const [stderr, exitCode] = await Promise.all([new Response(proc.stderr).text(), proc.exited])
      if (exitCode !== 0) {
        console.warn(`[dotfiles-harness] herdr title sync exited ${exitCode}: ${stderr.trim()}`)
        return false
      }
      appliedHerdrTitle = title
      return true
    } catch (error) {
      console.warn(`[dotfiles-harness] herdr title sync failed: ${error}`)
      return false
    } finally {
      herdrTitleSyncInFlight = false
    }
  }

  const startHerdrTitleSync = async (ctx: TitleSyncContext) => {
    if (ctx.mode !== "tui" || !herdrTarget) return
    activeTitleContext = ctx
    await syncHerdrTitle(ctx)
    if (titleSyncStarted) return
    titleSyncStarted = true
    ctx.setInterval(async () => {
      if (activeTitleContext) await syncHerdrTitle(activeTitleContext)
    }, 500)
  }

  const payloadFor = (sessionId: string, input: Record<string, unknown> | undefined) => ({
    session_id: sessionId,
    cwd: pi.cwd,
    tool_input: {
      command: stringField(input, "command", "patchText", "patch"),
      file_path: stringField(input, "filePath", "file_path", "path"),
      content: stringField(input, "content"),
      new_string: stringField(input, "newString", "new_string"),
    },
  })

  // Scope / verify / PR gates: block a tool call when a gate script exits 2.
  pi.on("tool_call", async (event, ctx) => {
    const tool = String(event.toolName ?? "").toLowerCase()
    const input = (event.input ?? {}) as Record<string, unknown>
    const sessionId = ctx?.sessionManager?.getSessionId?.() ?? ""
    const payload = payloadFor(sessionId, input)

    const command = shellCommand(input)
    if (invokesLavish(command)) {
      if (!shellTools.has(tool) || ctx.mode !== "tui") {
        return { block: true, reason: "Lavish is human-interactive TUI review only; use native search tools instead." }
      }
      if (/\blavish-axi(?:-safe)?\s+poll\b/.test(command) && input.async !== true) {
        return { block: true, reason: "Run Lavish poll as one managed Bash job with async: true." }
      }
    }

    if (editTools.has(tool)) {
      const result = await runHook(scopeGate, payload)
      if (result.exitCode === 2) return { block: true, reason: result.stderr.trim() }
      return
    }

    if (shellTools.has(tool)) {
      for (const script of [
        join(hooks, "verify-gate-pretooluse.sh"),
        join(hooks, "pr-authoring-gate-pretooluse.sh"),
      ]) {
        const result = await runHook(script, payload)
        if (result.exitCode === 2) return { block: true, reason: result.stderr.trim() }
      }
    }
  })

  // Comment self-check: after an edit, surface the reminder back to the model.
  pi.on("tool_result", async (event) => {
    const tool = String(event.toolName ?? "").toLowerCase()
    if (!editTools.has(tool)) return
    const input = (event.input ?? {}) as Record<string, unknown>
    const result = await runHook(join(hooks, "comment-self-check.sh"), {
      tool_input: {
        file_path: stringField(input, "filePath", "file_path", "path"),
        content: stringField(input, "content"),
        new_string: stringField(input, "newString", "new_string"),
      },
    })
    if (!result.stdout.trim()) return
    try {
      const parsed = JSON.parse(result.stdout)
      const reminder = parsed?.hookSpecificOutput?.additionalContext
      if (typeof reminder !== "string") return
      const prior = Array.isArray((event as { content?: unknown }).content)
        ? ((event as { content: unknown[] }).content)
        : []
      return { content: [...prior, { type: "text", text: reminder }] }
    } catch (error) {
      console.warn(`[dotfiles-harness] ignored invalid comment hook output: ${error}`)
    }
  })

  // Add omp-specific and scope guidance without scheduling another user turn.
  pi.on("before_agent_start", async (event, ctx) => {
    const systemPrompt = [...event.systemPrompt, lavishPollGuidance]
    const sessionId = ctx?.sessionManager?.getSessionId?.() ?? ""
    const result = await runHook(scopePrompt, { session_id: sessionId })
    const brief = result.stdout.trim()
    if (brief) systemPrompt.push(brief)
    return { systemPrompt }
  })

  pi.on("session_start", async (_event, ctx) => {
    await startHerdrTitleSync(ctx)
  })

  pi.on("turn_end", async (_event, ctx) => {
    if (ctx.mode !== "tui") return
    activeTitleContext = ctx
    await syncHerdrTitle(ctx)
  })

  // Slack attention: notify when a root session finishes or needs input. Herdr's
  // native integration already reports lifecycle state to the sidebar; this is the
  // separate personal-Slack channel the opencode harness also drove.
  pi.on("tool_approval_requested", async (event) => {
    notify(
      [
        "*omp needs your input*",
        `*Reason:* ${slackText(`Approval: ${String(event.toolName ?? "tool")}`)}`,
      ].join("\n"),
    )
  })

  pi.on("session_stop", async (_event, ctx) => {
    // Documented to fire for root sessions only, never for subagents.
    const usage = ctx?.getContextUsage?.()
    const detail = usage ? `*Context:* ${slackText(String(usage))}` : undefined
    notify(["*omp finished*", detail].filter(Boolean).join("\n"))
  })
}
