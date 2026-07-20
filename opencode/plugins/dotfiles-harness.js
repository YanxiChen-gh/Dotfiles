import { readFile, realpath } from "node:fs/promises"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const runHook = async (script, payload, extraEnv = {}) => {
  try {
    const process = Bun.spawn(["bash", script], {
      env: { ...Bun.env, ...extraEnv },
      stdin: new Blob([JSON.stringify(payload)]),
      stdout: "pipe",
      stderr: "pipe",
    })
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(process.stdout).text(),
      new Response(process.stderr).text(),
      process.exited,
    ])
    if (exitCode !== 0 && exitCode !== 2) {
      console.warn(`[dotfiles-harness] hook exited ${exitCode}: ${stderr.trim()}`)
    }
    return { stdout, stderr, exitCode }
  } catch (error) {
    console.warn(`[dotfiles-harness] hook failed open: ${error}`)
    return { stdout: "", stderr: "", exitCode: 0 }
  }
}

const defaultSessionTitle = /^New session - \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/

const createHerdrTitleSync = () => {
  const tabId = Bun.env.HERDR_TAB_ID
  if (Bun.env.HERDR_ENV !== "1" || !tabId) return async () => {}

  const herdr = Bun.env.HERDR_BIN_PATH ?? "herdr"
  let sessionId
  let appliedTitle
  let pendingTitle
  let renameQueue = Promise.resolve()

  const renameTab = async (title) => {
    try {
      const process = Bun.spawn([herdr, "tab", "rename", tabId, title], {
        env: Bun.env,
        stdin: "ignore",
        stdout: "ignore",
        stderr: "pipe",
      })
      const [stderr, exitCode] = await Promise.all([
        new Response(process.stderr).text(),
        process.exited,
      ])
      if (exitCode !== 0) {
        console.warn(`[dotfiles-harness] herdr tab rename exited ${exitCode}: ${stderr.trim()}`)
        return
      }
      appliedTitle = title
    } catch (error) {
      console.warn(`[dotfiles-harness] herdr tab rename failed: ${error}`)
    }
  }

  return async ({ event }) => {
    if (event.type !== "session.created" && event.type !== "session.updated") return

    const session = event.properties?.info
    if (!session || typeof session.id !== "string" || session.parentID) return

    if (!sessionId) {
      if (event.type !== "session.created") return
      sessionId = session.id
    }
    if (session.id !== sessionId || typeof session.title !== "string") return

    const title = session.title.trim()
    if (!title || defaultSessionTitle.test(title) || title === appliedTitle || title === pendingTitle) {
      return
    }

    pendingTitle = title
    renameQueue = renameQueue.then(async () => {
      await renameTab(title)
      if (pendingTitle === title) pendingTitle = undefined
    })
    await renameQueue
  }
}

const stringArg = (args, ...names) => {
  for (const name of names) {
    if (typeof args?.[name] === "string") return args[name]
  }
  return ""
}

const resolveEnvironment = (value) => {
  if (typeof value === "string") {
    return value.replace(
      /\{env:([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}/g,
      (_placeholder, name, fallback = "") => Bun.env[name] ?? fallback,
    )
  }
  if (Array.isArray(value)) return value.map(resolveEnvironment)
  if (!value || typeof value !== "object") return value
  return Object.fromEntries(
    Object.entries(value).map(([key, entry]) => [key, resolveEnvironment(entry)]),
  )
}

export const DotfilesHarnessPlugin = async ({ directory }, options = {}) => {
  const source = await realpath(fileURLToPath(import.meta.url))
  const dotfiles = dirname(dirname(dirname(source)))
  const home = Bun.env.HOME ?? ""
  const configHome = Bun.env.XDG_CONFIG_HOME ?? join(home, ".config")
  const maturity = Bun.env.AGENT_MATURITY_HOME ?? join(home, "agent-maturity")
  const scopePrompt = join(maturity, "scripts/scope-gate-userpromptsubmit.sh")
  const scopeGate = join(maturity, "scripts/scope-gate-pretooluse.sh")
  const hooks =
    typeof options.hooksDir === "string" ? options.hooksDir : join(dotfiles, "claude/hooks")
  const syncHerdrTitle = createHerdrTitleSync()

  return {
    event: syncHerdrTitle,
    config: async (config) => {
      try {
        const local = JSON.parse(
          await readFile(join(configHome, "opencode/mcp.json"), "utf8"),
        )
        if (local.mcp && typeof local.mcp === "object") {
          config.mcp = { ...config.mcp, ...resolveEnvironment(local.mcp) }
        }
      } catch (error) {
        if (error?.code !== "ENOENT") {
          console.warn(`[dotfiles-harness] ignored invalid MCP overlay: ${error}`)
        }
      }
    },
    "experimental.chat.system.transform": async (input, output) => {
      if (!input.sessionID) return
      const result = await runHook(scopePrompt, { session_id: input.sessionID })
      if (result.stdout.trim()) output.system.push(result.stdout.trim())
    },
    "tool.execute.before": async (input, output) => {
      const tool = input.tool.toLowerCase()
      const args = output.args
      const payload = {
        session_id: input.sessionID,
        cwd: directory,
        tool_input: {
          command: stringArg(args, "command", "patchText", "patch"),
          file_path: stringArg(args, "filePath", "file_path", "path"),
          content: stringArg(args, "content"),
          new_string: stringArg(args, "newString", "new_string"),
        },
      }

      if (["edit", "write", "apply_patch"].includes(tool)) {
        const result = await runHook(scopeGate, payload)
        if (result.exitCode === 2) throw new Error(result.stderr.trim())
      }

      if (["bash", "shell"].includes(tool)) {
        for (const script of [
          join(hooks, "verify-gate-pretooluse.sh"),
          join(hooks, "pr-authoring-gate-pretooluse.sh"),
        ]) {
          const result = await runHook(script, payload)
          if (result.exitCode === 2) throw new Error(result.stderr.trim())
        }
      }
    },
    "tool.execute.after": async (input, output) => {
      if (!["edit", "write"].includes(input.tool.toLowerCase())) return
      const result = await runHook(join(hooks, "comment-self-check.sh"), {
        tool_input: {
          file_path: stringArg(input.args, "filePath", "file_path", "path"),
          content: stringArg(input.args, "content"),
          new_string: stringArg(input.args, "newString", "new_string"),
        },
      })
      if (!result.stdout.trim()) return

      try {
        const parsed = JSON.parse(result.stdout)
        const reminder = parsed.hookSpecificOutput?.additionalContext
        if (typeof reminder === "string") output.output += `\n\n${reminder}`
      } catch (error) {
        console.warn(`[dotfiles-harness] ignored invalid comment hook output: ${error}`)
      }
    },
  }
}
