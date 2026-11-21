import { join } from "node:path"

// omp's public extension type. Runtime is Bun, so Bun.* is available at runtime;
// the import is type-only so a plain `bun`/`tsc` check does not need omp installed.
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent"

type TitleSyncContext = {
  mode: "tui" | "rpc" | "json" | "print"
  sessionManager: { getSessionName(): string | undefined }
  setInterval(callback: () => void | Promise<void>, ms?: number): unknown
}
type HerdrTitleTarget = { kind: "workspace" | "tab"; id: string }

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

export default async function dotfilesHarness(pi: ExtensionAPI) {
  if (
    Bun.env.HERDR_ENV === "1" &&
    Bun.env.HERDR_SOCKET_PATH &&
    Bun.env.HERDR_PANE_ID &&
    Bun.env.OMPCODE !== "1"
  ) {
    // Herdr's lifecycle integration owns root completion toasts; keep standalone OMP unchanged.
    // OMP supplies this module; plain Bun fixture runners cannot resolve it.
    const { lookup } = await import("@oh-my-pi/pi-coding-agent/config/registry")
    const completionNotify = lookup("completion.notify")
    if (!completionNotify) throw new Error("OMP completion.notify setting is unavailable")
    completionNotify.override(pi.pi.settings, "off")
  }

  const home = Bun.env.HOME ?? ""
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
