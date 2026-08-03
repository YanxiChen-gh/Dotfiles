import { readFile, realpath } from "node:fs/promises"
import { basename, dirname, join } from "node:path"
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
    return { stdout, stderr, exitCode, failed: false }
  } catch (error) {
    console.warn(`[dotfiles-harness] hook failed open: ${error}`)
    return { stdout: "", stderr: "", exitCode: 0, failed: true }
  }
}

const defaultSessionTitle = /^New session - \d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/

const createHerdrTitleSync = (directory) => {
  const tabId = Bun.env.HERDR_TAB_ID
  const workspaceId = Bun.env.HERDR_WORKSPACE_ID
  const taskWorkspace = Bun.env.DOTFILES_HERDR_TASK_WORKSPACE === "1" && workspaceId
  const target = taskWorkspace
    ? { kind: "workspace", id: workspaceId }
    : tabId
      ? { kind: "tab", id: tabId }
      : undefined
  if (Bun.env.HERDR_ENV !== "1" || !target) return async () => {}

  const herdr = Bun.env.HERDR_BIN_PATH ?? "herdr"
  let sessionId
  let appliedTitle
  let pendingTitle
  let renameQueue = Promise.resolve()
  let metadataApplied = !taskWorkspace
  let metadataPromise

  const gitOutput = async (...args) => {
    const process = Bun.spawn(["git", "-C", directory, ...args], {
      env: Bun.env,
      stdin: "ignore",
      stdout: "pipe",
      stderr: "pipe",
    })
    const [stdout, stderr, exitCode] = await Promise.all([
      new Response(process.stdout).text(),
      new Response(process.stderr).text(),
      process.exited,
    ])
    if (exitCode !== 0) {
      throw new Error(`git ${args.join(" ")} exited ${exitCode}: ${stderr.trim()}`)
    }
    return stdout.trim()
  }

  const reportCheckoutMetadata = async () => {
    try {
      const currentWorktree = await gitOutput("rev-parse", "--show-toplevel")
      const worktreeList = await gitOutput("worktree", "list", "--porcelain")
      const primaryWorktree = worktreeList
        .split("\n")
        .find((line) => line.startsWith("worktree "))
        ?.slice("worktree ".length)
      if (!primaryWorktree) throw new Error("git worktree list returned no primary checkout")

      const repoName = basename(primaryWorktree)
      let worktreeName = basename(currentWorktree)
      if (currentWorktree === primaryWorktree) {
        worktreeName = "primary"
      } else if (worktreeName === repoName) {
        worktreeName = basename(dirname(currentWorktree))
      }

      const process = Bun.spawn(
        [
          herdr,
          "workspace",
          "report-metadata",
          workspaceId,
          "--source",
          "dotfiles:checkout",
          "--token",
          `repo=${repoName}`,
          "--token",
          `worktree=${worktreeName}`,
        ],
        {
          env: Bun.env,
          stdin: "ignore",
          stdout: "ignore",
          stderr: "pipe",
        },
      )
      const [stderr, exitCode] = await Promise.all([
        new Response(process.stderr).text(),
        process.exited,
      ])
      if (exitCode !== 0) {
        console.warn(
          `[dotfiles-harness] herdr workspace report-metadata exited ${exitCode}: ${stderr.trim()}`,
        )
        return
      }
      metadataApplied = true
    } catch (error) {
      console.warn(`[dotfiles-harness] checkout metadata sync failed: ${error}`)
    }
  }

  const syncCheckoutMetadata = async () => {
    if (metadataApplied) return
    metadataPromise ??= reportCheckoutMetadata().finally(() => {
      metadataPromise = undefined
    })
    await metadataPromise
  }

  const renameTarget = async (title) => {
    try {
      const process = Bun.spawn([herdr, target.kind, "rename", target.id, title], {
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
        console.warn(
          `[dotfiles-harness] herdr ${target.kind} rename exited ${exitCode}: ${stderr.trim()}`,
        )
        return
      }
      appliedTitle = title
    } catch (error) {
      console.warn(`[dotfiles-harness] herdr ${target.kind} rename failed: ${error}`)
    }
  }

  return async ({ event }) => {
    if (event.type !== "session.created" && event.type !== "session.updated") return

    const session = event.properties?.info
    if (!session || typeof session.id !== "string" || session.parentID) return

    if (!sessionId) {
      sessionId = session.id
    }
    if (session.id !== sessionId || typeof session.title !== "string") return

    await syncCheckoutMetadata()

    const title = session.title.trim()
    if (!title || defaultSessionTitle.test(title) || title === appliedTitle || title === pendingTitle) {
      return
    }

    pendingTitle = title
    renameQueue = renameQueue.then(async () => {
      await renameTarget(title)
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

const subagentContext = `[subagent]
This is a child session. Do not launch Lavish, call question or approval tools, or wait for human input. Return findings, questions, and blockers directly to the parent. The parent owns scope approval.`

const invokesLavish = (command) => {
  return command.includes("lavish-axi")
}

export const DotfilesHarnessPlugin = async ({ client, directory }, options = {}) => {
  const source = await realpath(fileURLToPath(import.meta.url))
  const dotfiles = dirname(dirname(dirname(source)))
  const home = Bun.env.HOME ?? ""
  const configHome = Bun.env.XDG_CONFIG_HOME ?? join(home, ".config")
  const maturity = Bun.env.AGENT_MATURITY_HOME ?? join(home, "agent-maturity")
  const scopePrompt = join(maturity, "scripts/scope-gate-userpromptsubmit.sh")
  const scopeGate = join(maturity, "scripts/scope-gate-pretooluse.sh")
  const hooks =
    typeof options.hooksDir === "string" ? options.hooksDir : join(dotfiles, "claude/hooks")
  const syncHerdrTitle = createHerdrTitleSync(directory)
  const parentBySession = new Map()
  const rootSessions = new Set()

  const rememberSession = (session) => {
    if (typeof session?.id !== "string") return
    if (typeof session.parentID === "string") {
      parentBySession.set(session.id, session.parentID)
      rootSessions.delete(session.id)
      return
    }
    rootSessions.add(session.id)
  }

  const hydrateSession = async (sessionID) => {
    if (parentBySession.has(sessionID) || rootSessions.has(sessionID)) return true
    if (!client?.session?.get) return false
    try {
      const result = await client.session.get({
        path: { id: sessionID },
        query: { directory },
      })
      rememberSession(result.data)
      return parentBySession.has(sessionID) || rootSessions.has(sessionID)
    } catch {
      return false
    }
  }

  const sessionLineage = async (sessionID) => {
    let current = sessionID
    let isChild = false
    const visited = new Set()
    while (!visited.has(current)) {
      visited.add(current)
      if (!(await hydrateSession(current))) return { kind: "unresolved" }
      const parent = parentBySession.get(current)
      if (!parent) {
        return {
          kind: isChild ? "child" : "root",
          rootSessionID: current,
        }
      }
      isChild = true
      current = parent
    }
    return { kind: "unresolved" }
  }
  return {
    event: async (input) => {
      const session = input.event.properties?.info
      if (input.event.type === "session.created" || input.event.type === "session.updated") {
        rememberSession(session)
      }
      await syncHerdrTitle(input)
    },
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
      const lineage = await sessionLineage(input.sessionID)
      if (lineage.kind !== "root") {
        output.system.push(subagentContext)
        return
      }
      const result = await runHook(scopePrompt, { session_id: input.sessionID })
      if (result.stdout.trim()) output.system.push(result.stdout.trim())
    },
    "tool.execute.before": async (input, output) => {
      const tool = input.tool.toLowerCase()
      const args = output.args
      const lineage = await sessionLineage(input.sessionID)
      const isChild = lineage.kind !== "root"

      if (isChild && tool === "question") {
        throw new Error("Subagents must return questions to their parent instead of waiting for human input.")
      }
      if (isChild && ["bash", "shell"].includes(tool) && invokesLavish(stringArg(args, "command"))) {
        throw new Error(
          "Subagents must not launch Lavish; use native search tools for inspection or return the review artifact or blocker to the parent.",
        )
      }

      if (lineage.kind === "unresolved" && ["edit", "write", "apply_patch"].includes(tool)) {
        throw new Error(
          "The root session approval could not be resolved. Stop and return this blocker to the parent.",
        )
      }

      const payload = {
        session_id: lineage.kind === "unresolved" ? input.sessionID : lineage.rootSessionID,
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
        if (isChild && (result.failed || (result.exitCode !== 0 && result.exitCode !== 2))) {
          throw new Error(
            "The root session approval could not be verified. Stop and return this blocker to the parent.",
          )
        }
        if (result.exitCode === 2) {
          if (isChild) {
            throw new Error(
              "The root session has not recorded approval for this edit. Stop and return this blocker to the parent.",
            )
          }
          throw new Error(result.stderr.trim())
        }
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
