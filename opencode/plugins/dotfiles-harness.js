import { appendFile, mkdir, readFile, realpath } from "node:fs/promises"
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

const sessionIDFromEvent = ({ event }) => {
  const properties = event.properties ?? {}
  if (typeof properties.sessionID === "string") return properties.sessionID
  if (typeof properties.info?.sessionID === "string") return properties.info.sessionID
  if (
    ["session.created", "session.updated", "session.deleted"].includes(event.type) &&
    typeof properties.info?.id === "string"
  ) {
    return properties.info.id
  }
  return undefined
}

const createHerdrTitleSync = (directory, rootSession) => {
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
    const eventSessionID = sessionIDFromEvent({ event })
    if (event.type === "session.deleted" && eventSessionID === rootSession.id) {
      rootSession.id = undefined
      appliedTitle = undefined
      pendingTitle = undefined
      return
    }
    if (event.type !== "session.created" && event.type !== "session.updated") return

    const session = event.properties?.info
    if (!session || typeof session.id !== "string" || session.parentID) return

    if (!rootSession.id) {
      rootSession.id = session.id
    }
    if (session.id !== rootSession.id || typeof session.title !== "string") return

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

const createHerdrSubagentSync = ({ rootSession, sessionLineage }) => {
  const paneId = Bun.env.HERDR_PANE_ID
  if (Bun.env.HERDR_ENV !== "1" || !paneId) return async () => {}

  const herdr = Bun.env.HERDR_BIN_PATH ?? "herdr"
  const tokenNames = ["subagent_1", "subagent_2", "subagent_3", "subagent_summary"]
  const children = new Map()
  let trackedRootSessionID
  let completedCount = 0
  let updateOrder = 0
  let appliedSignature

  const childTitle = (session) => {
    const value =
      typeof session?.title === "string" && session.title.trim()
        ? session.title.trim().replace(/\s+\(@[^)]+ subagent\)$/, "")
        : typeof session?.agent === "string" && session.agent.trim()
          ? session.agent.trim()
          : "subagent"
    return value.slice(0, 64)
  }

  const reportMetadata = async (values) => {
    const args = [
      herdr,
      "pane",
      "report-metadata",
      paneId,
      "--source",
      "dotfiles:opencode-subagents",
      "--agent",
      "opencode",
    ]
    for (const name of tokenNames) {
      const value = values[name]
      if (value) {
        args.push("--token", `${name}=${value}`)
      } else {
        args.push("--clear-token", name)
      }
    }

    let failure
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        const process = Bun.spawn(args, {
          env: Bun.env,
          stdin: "ignore",
          stdout: "ignore",
          stderr: "pipe",
        })
        const [stderr, exitCode] = await Promise.all([
          new Response(process.stderr).text(),
          process.exited,
        ])
        if (exitCode === 0) return true
        failure = `exited ${exitCode}: ${stderr.trim()}`
      } catch (error) {
        failure = `failed: ${error}`
      }
    }
    console.warn(`[dotfiles-harness] herdr pane report-metadata ${failure}`)
    return false
  }

  const syncMetadata = async () => {
    const priority = { blocked: 0, error: 1, retry: 2, working: 3 }
    const active = [...children.values()]
      .filter((child) => child.state !== "idle")
      .sort((left, right) => priority[left.state] - priority[right.state] || right.order - left.order)
    const prefixes = { blocked: "[ask]", error: "[error]", retry: "[retry]", working: "[run]" }
    const values = {}
    for (const [index, child] of active.slice(0, 3).entries()) {
      values[`subagent_${index + 1}`] = `${prefixes[child.state]} ${child.title}`
    }

    const summary = []
    if (active.length > 3) summary.push(`+${active.length - 3} active`)
    if (completedCount > 0) summary.push(`${completedCount} completed`)
    if (summary.length > 0) values.subagent_summary = summary.join(" / ")

    const signature = JSON.stringify(values)
    if (signature === appliedSignature) return
    if (await reportMetadata(values)) appliedSignature = signature
  }

  const resetForRoot = async (rootSessionID) => {
    if (trackedRootSessionID === rootSessionID) return false
    trackedRootSessionID = rootSessionID
    children.clear()
    completedCount = 0
    await syncMetadata()
    return true
  }

  return async (input) => {
    const { event } = input
    const eventSessionID = sessionIDFromEvent(input)
    await resetForRoot(rootSession.id)

    if (event.type === "session.deleted" && eventSessionID === trackedRootSessionID) {
      trackedRootSessionID = undefined
      children.clear()
      completedCount = 0
      await syncMetadata()
      return
    }
    if (!eventSessionID || !trackedRootSessionID) return

    const lineage = await sessionLineage(eventSessionID)
    if (lineage.kind !== "child" || lineage.rootSessionID !== trackedRootSessionID) return

    const session =
      event.type === "session.created" || event.type === "session.updated"
        ? event.properties?.info
        : undefined
    let child = children.get(eventSessionID)
    if (!child) {
      child = { title: childTitle(session), state: "idle", order: 0, completed: false }
      children.set(eventSessionID, child)
    } else if (session) {
      child.title = childTitle(session)
    }

    const markActive = (state) => {
      child.state = state
      child.completed = false
      updateOrder += 1
      child.order = updateOrder
    }
    const markCompleted = () => {
      if (!child.completed && child.state !== "idle") completedCount += 1
      child.state = "idle"
      child.completed = true
    }

    switch (event.type) {
      case "session.created":
        markActive("working")
        break
      case "session.status": {
        const status =
          typeof event.properties?.status === "string"
            ? event.properties.status
            : event.properties?.status?.type
        if (status === "idle") markCompleted()
        else if (status === "retry") markActive("retry")
        else if (status === "busy") markActive("working")
        break
      }
      case "session.idle":
        markCompleted()
        break
      case "permission.asked":
      case "question.asked":
        markActive("blocked")
        break
      case "permission.replied":
      case "question.replied":
      case "question.rejected":
        markActive("working")
        break
      case "session.error":
        markActive("error")
        break
      case "session.deleted":
        children.delete(eventSessionID)
        break
      default:
        break
    }
    await syncMetadata()
  }
}

const createActiveDescendantSync = ({ sessionLineage }) => {
  const descendants = new Map()

  const stateFor = (sessionID, rootSessionID) => {
    let state = descendants.get(sessionID)
    if (!state) {
      state = {
        rootSessionID,
        status: "idle",
        permissions: new Set(),
        questions: new Set(),
      }
      descendants.set(sessionID, state)
    }
    return state
  }

  const requestID = (event) => event.properties?.requestID ?? event.properties?.id

  return {
    hasActive(rootSessionID) {
      return [...descendants.values()].some(
        (state) =>
          state.rootSessionID === rootSessionID &&
          (state.status !== "idle" || state.permissions.size > 0 || state.questions.size > 0),
      )
    },
    async handleEvent(input) {
      const sessionID = sessionIDFromEvent(input)
      if (!sessionID) return

      const lineage = await sessionLineage(sessionID)
      if (lineage.kind === "root") {
        if (input.event.type === "session.deleted") {
          for (const [childSessionID, state] of descendants) {
            if (state.rootSessionID === lineage.rootSessionID) descendants.delete(childSessionID)
          }
        }
        return
      }
      if (lineage.kind !== "child") return

      if (input.event.type === "session.deleted") {
        descendants.delete(sessionID)
        return
      }

      const state = stateFor(sessionID, lineage.rootSessionID)
      switch (input.event.type) {
        case "session.created":
        case "tool.execute.before":
        case "tool.execute.after":
          state.status = "working"
          break
        case "session.status": {
          const status =
            typeof input.event.properties?.status === "string"
              ? input.event.properties.status
              : input.event.properties?.status?.type
          if (status === "idle") state.status = "idle"
          else if (status === "busy" || status === "retry") state.status = "working"
          break
        }
        case "session.idle":
          state.status = "idle"
          break
        case "permission.asked": {
          const id = requestID(input.event)
          if (typeof id === "string") state.permissions.add(id)
          state.status = "blocked"
          break
        }
        case "permission.replied": {
          const id = requestID(input.event)
          if (typeof id === "string") state.permissions.delete(id)
          state.status = "working"
          break
        }
        case "question.asked": {
          const id = requestID(input.event)
          if (typeof id === "string") state.questions.add(id)
          state.status = "blocked"
          break
        }
        case "question.replied":
        case "question.rejected": {
          const id = requestID(input.event)
          if (typeof id === "string") state.questions.delete(id)
          state.status = "working"
          break
        }
        case "session.error":
          state.status = "error"
          break
        default:
          break
      }
    },
  }
}

const createSlackSender = (home) => {
  const executable = Bun.env.SLACK_NOTIFY_BIN ?? join(home, ".local/bin/slack-webhook-post.sh")

  return (message) => {
    if (Bun.env.AGENT_SLACK_NOTIFICATIONS === "0") return

    try {
      const process = Bun.spawn([executable, "default", "-"], {
        env: Bun.env,
        stdin: new Blob([message]),
        stdout: "ignore",
        stderr: "ignore",
      })
      void process.exited
        .then((exitCode) => {
          if (exitCode !== 0 && exitCode !== 2) {
            console.warn(`[dotfiles-harness] Slack notification failed (exit ${exitCode})`)
          }
        })
        .catch(() => {
          console.warn("[dotfiles-harness] Slack notification failed")
        })
    } catch {
      console.warn("[dotfiles-harness] Slack notification failed")
    }
  }
}

const slackText = (value, maxLength = 160) => {
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

const workspaceName = (directory) => {
  if (typeof directory !== "string" || !directory) return "unknown"
  const parts = directory.split("/").filter(Boolean)
  const repository = parts.at(-1) ?? directory
  const parent = parts.at(-2)
  return /^\d+$/.test(parent ?? "") ? `${repository} / worktree ${parent}` : repository
}

const createSlackMessage = ({ kind, session, details = [] }) => {
  const title =
    typeof session?.title === "string" &&
    session.title.trim() &&
    !defaultSessionTitle.test(session.title.trim())
      ? session.title
      : "Untitled OpenCode session"
  const headings = {
    blockedPermission: "*OpenCode needs your input*",
    blockedQuestion: "*OpenCode needs your input*",
    error: "*OpenCode needs attention*",
    finished: "*OpenCode finished*",
  }
  const lines = [
    headings[kind],
    `*Task:* ${slackText(title, 120)}`,
    `*Workspace:* ${slackText(workspaceName(session?.directory), 100)}`,
  ]
  if (typeof session?.agent === "string" && session.agent.trim()) {
    lines.push(`*Agent:* ${slackText(session.agent, 40)}`)
  }
  lines.push(...details.filter(Boolean))
  return lines.join("\n")
}

const createSlackNotificationSync = ({
  sessionLineage,
  sessionInfo,
  notify,
  suppressIdle,
  permissionDelayMs = 3_000,
}) => {
  const states = new Map()

  const stateFor = (sessionID) => {
    let state = states.get(sessionID)
    if (!state) {
      state = {
        active: false,
        waiting: undefined,
        notification: undefined,
        permissions: new Map(),
        questions: new Map(),
        permissionNotified: false,
        questionNotified: false,
        permissionTimer: undefined,
      }
      states.set(sessionID, state)
    }
    return state
  }

  const dispatch = (message) => {
    queueMicrotask(() => {
      try {
        void Promise.resolve(notify(message)).catch(() => {
          console.warn("[dotfiles-harness] Slack notification failed")
        })
      } catch {
        console.warn("[dotfiles-harness] Slack notification failed")
      }
    })
  }

  const message = (kind, sessionID, details) =>
    createSlackMessage({ kind, session: sessionInfo(sessionID), details })

  const clearPermissionTimer = (state) => {
    if (state.permissionTimer) clearTimeout(state.permissionTimer)
    state.permissionTimer = undefined
  }

  const clearPermissions = (state) => {
    clearPermissionTimer(state)
    state.permissions.clear()
    state.permissionNotified = false
  }

  const schedulePermissionNotification = (sessionID, state) => {
    if (
      state.permissionTimer ||
      state.permissions.size === 0 ||
      state.permissionNotified
    ) {
      return
    }
    state.permissionTimer = setTimeout(() => {
      state.permissionTimer = undefined
      if (state.permissions.size === 0 || state.questions.size > 0) return

      const requests = [...state.permissions.values()]
      const permissions = [...new Set(requests.map((request) => request.permission).filter(Boolean))]
      const details = [
        `*Reason:* ${slackText(`Permission: ${permissions.join(", ") || "approval required"}`)}`,
        requests.length > 1 ? `*Requests:* ${requests.length}` : undefined,
      ]
      state.waiting = "input"
      state.permissionNotified = true
      state.notification = "blocked-permission"
      dispatch(message("blockedPermission", sessionID, details))
    }, permissionDelayMs)
    state.permissionTimer.unref?.()
  }

  const markWorking = async (sessionID) => {
    if (!sessionID) return
    const lineage = await sessionLineage(sessionID)
    if (lineage.kind !== "root") return

    const state = stateFor(lineage.rootSessionID)
    state.active = true
    if (state.questions.size === 0 && state.permissions.size === 0) {
      state.waiting = undefined
      state.notification = undefined
    }
  }

  const handleEvent = async (input) => {
    const sessionID = sessionIDFromEvent(input)
    if (!sessionID) return

    const lineage = await sessionLineage(sessionID)
    if (lineage.kind !== "root") return
    const rootSessionID = lineage.rootSessionID

    if (input.event.type === "session.deleted") {
      const state = states.get(rootSessionID)
      if (state) clearPermissionTimer(state)
      states.delete(rootSessionID)
      return
    }

    const state = stateFor(rootSessionID)
    const markActive = () => {
      state.active = true
      if (state.questions.size === 0 && state.permissions.size === 0) {
        state.waiting = undefined
        state.notification = undefined
      }
    }
    const markIdle = () => {
      if (state.questions.size > 0 || state.permissions.size > 0 || suppressIdle(rootSessionID)) return
      if (state.waiting === "overflow") {
        state.active = false
        state.waiting = "error"
        state.notification = "error"
        dispatch(
          message("error", rootSessionID, ["*Reason:* Context limit recovery did not resume"]),
        )
      } else if (state.active && !state.waiting && state.notification !== "finished") {
        state.active = false
        state.notification = "finished"
        const summary = sessionInfo(rootSessionID)?.summary
        const changes =
          Number.isFinite(summary?.files) && summary.files > 0
            ? `*Changes:* ${summary.files} files / +${summary.additions ?? 0} / -${summary.deletions ?? 0}`
            : undefined
        dispatch(message("finished", rootSessionID, [changes]))
      }
    }

    switch (input.event.type) {
      case "session.status": {
        const status =
          typeof input.event.properties?.status === "string"
            ? input.event.properties.status
            : input.event.properties?.status?.type
        if (status === "busy" || status === "retry") {
          markActive()
        } else if (status === "idle") markIdle()
        break
      }
      case "session.idle":
        markIdle()
        break
      case "tool.execute.before":
      case "tool.execute.after":
        markActive()
        break
      case "permission.asked": {
        const requestID = input.event.properties?.id
        if (typeof requestID !== "string") break
        const firstPendingPermission = state.permissions.size === 0
        state.active = true
        state.waiting = "permission"
        if (firstPendingPermission) state.notification = undefined
        state.permissions.set(requestID, {
          permission: input.event.properties?.permission,
        })
        schedulePermissionNotification(rootSessionID, state)
        break
      }
      case "permission.replied": {
        const requestID = input.event.properties?.requestID
        if (typeof requestID === "string") state.permissions.delete(requestID)
        if (state.permissions.size === 0) {
          clearPermissionTimer(state)
          state.permissionNotified = false
          markActive()
        }
        break
      }
      case "question.asked": {
        const requestID = input.event.properties?.id
        if (typeof requestID !== "string") break
        const firstPendingQuestion = state.questions.size === 0
        state.waiting = "input"
        const headers = (input.event.properties?.questions ?? [])
          .map((question) => question?.header)
          .filter((header) => typeof header === "string" && header.trim())
        if (firstPendingQuestion) state.questionNotified = false
        state.questions.set(requestID, headers)
        if (state.questionNotified) break
        state.questionNotified = true
        state.notification = "blocked-question"
        dispatch(
          message("blockedQuestion", rootSessionID, [
            `*Question:* ${slackText(headers.join(", ") || "Response requested")}`,
          ]),
        )
        break
      }
      case "question.replied":
      case "question.rejected": {
        const requestID = input.event.properties?.requestID
        if (typeof requestID === "string") state.questions.delete(requestID)
        if (state.questions.size === 0) {
          state.questionNotified = false
          markActive()
          schedulePermissionNotification(rootSessionID, state)
        }
        break
      }
      case "session.error":
        clearPermissions(state)
        state.questions.clear()
        state.questionNotified = false
        if (input.event.properties?.error?.name === "MessageAbortedError") {
          state.active = false
          state.waiting = undefined
          state.notification = undefined
          break
        }
        if (input.event.properties?.error?.name === "ContextOverflowError") {
          state.waiting = "overflow"
          state.notification = undefined
          break
        }
        state.waiting = "error"
        if (state.notification !== "error") {
          state.notification = "error"
          const errorName = input.event.properties?.error?.name
          dispatch(
            message("error", rootSessionID, [
              `*Reason:* ${slackText(errorName || "Session error")}`,
            ]),
          )
        }
        break
      default:
        break
    }
  }

  return { handleEvent, markWorking }
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

const checkpointToolName = "context_checkpoint"
const canaryPreflightToolName = "canary_takeover_preflight"
const canaryCompleteToolName = "canary_takeover_complete"
const compactionTimeoutMs = 60_000

const createCanaryPreflight = async ({
  client,
  directory,
  home,
  maturity,
  stateHome,
  sessionLineage,
}) => {
  const automatic = Bun.env.OPENCODE_CANARY_TAKEOVER !== "0"
  const maturityData = Bun.env.AGENT_MATURITY_DATA_DIR ?? join(home, ".agent-maturity-data")
  const takeoverDirectory = join(maturityData, "takeovers")
  const auditDirectory = join(stateHome ?? join(home, ".local/state"), "opencode")
  const auditPath = join(auditDirectory, "canary-takeovers.jsonl")
  const states = new Map()

  try {
    const contents = await readFile(auditPath, "utf8")
    for (const line of contents.split("\n")) {
      if (!line.trim()) continue
      try {
        const record = JSON.parse(line)
        if (typeof record.sessionID !== "string") continue
        if (record.event === "reset") states.delete(record.sessionID)
        if (record.event === "started") {
          if (typeof record.attemptID === "string") {
            states.set(record.sessionID, {
              phase: "awaiting_record",
              preflightStatus: record.preflightStatus,
              attemptID: record.attemptID,
            })
          }
        }
        if (record.event === "completed") states.set(record.sessionID, { phase: "completed" })
      } catch {
        // Ignore partial audit lines; the terminal evidence record remains authoritative.
      }
    }
  } catch (error) {
    if (error?.code !== "ENOENT") console.warn(`[dotfiles-harness] ignored invalid canary audit: ${error}`)
  }

  const audit = async (event, sessionID, details = {}) => {
    await mkdir(auditDirectory, { recursive: true })
    await appendFile(
      auditPath,
      `${JSON.stringify({ at: new Date().toISOString(), event, sessionID, ...details })}\n`,
    )
  }
  const run = async (command) => {
    const process = Bun.spawn(command, {
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
    return { stdout: stdout.trim(), stderr: stderr.trim(), exitCode }
  }
  const start = async (sessionID, preflightStatus, error) => {
    const nonce = globalThis.crypto?.randomUUID?.().slice(0, 8) ?? Math.random().toString(16).slice(2, 10)
    const attemptID = `canary-${Date.now()}-${sessionID}-${nonce}`
    states.set(sessionID, { phase: "awaiting_record", preflightStatus, attemptID, error })
    await audit("started", sessionID, { preflightStatus, attemptID, error })
    return attemptID
  }
  const unavailable = async (sessionID, output, error) => {
    const attemptID = await start(sessionID, "unavailable", error)
    return {
      title: "Canary preflight unavailable",
      output,
      metadata: { status: "unavailable", attemptID, error },
    }
  }
  const terminalRecord = async (sessionID, attemptID) => {
    const name = `${attemptID}.json`
    const path = join(takeoverDirectory, name)
    let record
    try {
      record = JSON.parse(await readFile(path, "utf8"))
    } catch (error) {
      if (error?.code === "ENOENT") return undefined
      return undefined
    }
    if (record.source_session_id !== sessionID) return undefined
    if (!["passed", "failed", "aborted"].includes(record.status)) return undefined

    const validation = await run([
      "jq",
      "-e",
      "--arg",
      "kind",
      "record",
      "--arg",
      "takeover_id",
      attemptID,
      "-f",
      join(maturity, "scripts/canary-takeover-schema.jq"),
      path,
    ])
    if (validation.exitCode !== 0) return undefined

    const relativePath = `takeovers/${name}`
    const commit = await run([
      "git",
      "-C",
      maturityData,
      "log",
      "-1",
      "--format=%H",
      "--",
      relativePath,
    ])
    if (commit.exitCode !== 0 || !commit.stdout) return undefined
    const [committedBlob, workingBlob] = await Promise.all([
      run(["git", "-C", maturityData, "rev-parse", `${commit.stdout}:${relativePath}`]),
      run(["git", "-C", maturityData, "hash-object", path]),
    ])
    if (
      committedBlob.exitCode !== 0 ||
      workingBlob.exitCode !== 0 ||
      committedBlob.stdout !== workingBlob.stdout
    ) return undefined
    const synced = await run([
      "git",
      "-C",
      maturityData,
      "merge-base",
      "--is-ancestor",
      commit.stdout,
      "@{upstream}",
    ])
    return synced.exitCode === 0 ? record : undefined
  }

  return {
    requirement(sessionID) {
      if (!automatic) return undefined
      const phase = states.get(sessionID)?.phase
      if (phase === "completed") return undefined
      return phase === "awaiting_record" ? "complete" : "start"
    },
    async event(event) {
      if (event.type !== "session.deleted") return
      const sessionID = event.properties?.info?.id
      if (typeof sessionID !== "string") return
      states.delete(sessionID)
      await audit("reset", sessionID)
    },
    preflightTool: {
      description:
        "Check that an OpenCode root session has no active descendants before launching a canary takeover. Read-only; call immediately before the fresh successor task.",
      args: {},
      async execute(_args, context) {
        const lineage = await sessionLineage(context.sessionID)
        if (lineage.kind !== "root") {
          return {
            title: "Canary preflight unavailable",
            output: "Canary takeover preflight is available only to root sessions.",
            metadata: { status: "unavailable" },
          }
        }
        if (states.get(context.sessionID)?.phase === "awaiting_record") {
          return {
            title: "Canary evidence pending",
            output: "Finish the current canary and record its terminal evidence before checkpointing.",
            metadata: { status: "awaiting_record" },
          }
        }
        if (!client?.session?.status) {
          return await unavailable(
            context.sessionID,
            "This OpenCode client cannot inspect descendant session status. Record an aborted canary before checkpointing.",
            "session status APIs unavailable",
          )
        }

        try {
          const result = await client.session.status({ query: { directory } })
          if (!result.data || typeof result.data !== "object") {
            throw new Error("status lookup returned no data")
          }
          const active = []
          for (const [sessionID, value] of Object.entries(result.data)) {
            if (sessionID === context.sessionID) continue
            const status = typeof value === "string" ? value : value?.type
            if (status === "idle") continue
            const candidate = await sessionLineage(sessionID)
            if (candidate.kind === "unresolved") {
              throw new Error(`lineage unavailable for active session ${sessionID}`)
            }
            if (candidate.kind === "child" && candidate.rootSessionID === context.sessionID) {
              active.push({ sessionID, status: status ?? "unknown" })
            }
          }
          if (active.length > 0) {
            return {
              title: "Canary preflight blocked",
              output: `${active.length} descendant session(s) are still active. Wait for them to become terminal before launching the canary.`,
              metadata: { status: "blocked", active },
            }
          }

          const attemptID = await start(context.sessionID, "ready")
          return {
            title: "Canary preflight ready",
            output: "No active descendants found.",
            metadata: { status: "ready", attemptID, active: [] },
          }
        } catch (error) {
          return await unavailable(
            context.sessionID,
            "Descendant status could not be verified. Record an aborted canary before checkpointing.",
            String(error),
          )
        }
      },
    },
    completeTool: {
      description:
        "Complete the current canary after terminal evidence has been recorded and synced. Read-only; required before the first context checkpoint can proceed.",
      args: {},
      async execute(_args, context) {
        const lineage = await sessionLineage(context.sessionID)
        if (lineage.kind !== "root") {
          return {
            title: "Canary completion unavailable",
            output: "Canary completion is available only to root sessions.",
            metadata: { status: "unavailable" },
          }
        }
        const state = states.get(context.sessionID)
        if (state?.phase === "completed") {
          return {
            title: "Canary already complete",
            output: "The automatic canary requirement is already satisfied for this root session.",
            metadata: { status: "completed" },
          }
        }
        if (state?.phase !== "awaiting_record") {
          return {
            title: "Canary completion blocked",
            output: "Run canary_takeover_preflight before completing the canary.",
            metadata: { status: "blocked" },
          }
        }

        let record
        try {
          record = await terminalRecord(context.sessionID, state.attemptID)
        } catch (error) {
          return {
            title: "Canary completion blocked",
            output: "Terminal canary evidence could not be validated against its upstream repository.",
            metadata: { status: "blocked", error: String(error) },
          }
        }
        if (!record) {
          return {
            title: "Canary completion blocked",
            output: "No terminal canary evidence record was found for this attempt.",
            metadata: { status: "blocked" },
          }
        }
        if (
          state.preflightStatus === "unavailable" &&
          (record.status !== "aborted" || record.reconciliation?.mismatches?.length === 0)
        ) {
          return {
            title: "Canary completion blocked",
            output: "Unavailable preflight evidence must be aborted and preserve its reason in reconciliation.mismatches.",
            metadata: { status: "blocked" },
          }
        }

        states.set(context.sessionID, { phase: "completed" })
        await audit("completed", context.sessionID, { takeoverID: record.takeover_id })
        return {
          title: "Canary complete",
          output: "The first-pressure canary requirement is satisfied. Context checkpointing may proceed.",
          metadata: { status: "completed", takeoverID: record.takeover_id },
        }
      },
    },
  }
}

const ratioFromEnvironment = (name, fallback) => {
  const value = Number(Bun.env[name])
  return Number.isFinite(value) && value > 0 && value < 1 ? value : fallback
}

const tokenCount = (tokens) => {
  if (Number.isFinite(tokens?.total)) return tokens.total
  return [
    tokens?.input,
    tokens?.output,
    tokens?.cache?.read,
    tokens?.cache?.write,
  ].reduce((total, value) => total + (Number.isFinite(value) ? value : 0), 0)
}

const usableContext = (model, reserved) => {
  const input = model?.limit?.input
  const context = model?.limit?.context
  const output = Number.isFinite(model?.limit?.output) ? model.limit.output : 0
  const buffer = Number.isFinite(reserved) ? reserved : Math.min(20_000, output)
  if (Number.isFinite(input) && input > 0) return Math.max(0, input - buffer)
  if (Number.isFinite(context) && context > 0) return Math.max(0, context - output)
  return 0
}

const checkpointCompactionContext = `[context checkpoint]
Produce a task-continuation checkpoint, not a conversation recap. Preserve only durable information needed to continue correctly:
- the user's current objective and the exact approved scope or scope brief reference
- decisions and constraints that still govern the work
- changed files and the meaningful state of the worktree
- verification already completed and its result
- unresolved blockers, risks, and user decisions
- the single next action and any remaining ordered work
Treat the repository, artifacts, and test results as sources of truth. Omit superseded exploration, repetitive tool output, and completed implementation detail that can be reconstructed from the code.`

const createCheckpointAutomation = ({
  client,
  directory,
  home,
  stateHome,
  sessionLineage,
  canaryRequirement,
}) => {
  const softRatio = ratioFromEnvironment("OPENCODE_CHECKPOINT_SOFT_RATIO", 0.5)
  const hardRatio = Math.max(
    softRatio,
    ratioFromEnvironment("OPENCODE_CHECKPOINT_HARD_RATIO", 0.75),
  )
  const auditDirectory = join(stateHome ?? join(home, ".local/state"), "opencode")
  const auditPath = join(auditDirectory, "context-checkpoints.jsonl")
  const sessions = new Map()
  let compactionReserved
  let auditQueue = Promise.resolve()

  const stateFor = (sessionID) => {
    let state = sessions.get(sessionID)
    if (!state) {
      state = {
        status: "ready",
        level: "none",
        auditedLevel: "none",
      }
      sessions.set(sessionID, state)
    }
    return state
  }

  const audit = async (event, sessionID, details = {}) => {
    const record = `${JSON.stringify({
      timestamp: new Date().toISOString(),
      event,
      session_id: sessionID,
      directory,
      ...details,
    })}\n`
    auditQueue = auditQueue
      .then(async () => {
        await mkdir(auditDirectory, { recursive: true })
        await appendFile(auditPath, record, { encoding: "utf8", mode: 0o600 })
      })
      .catch((error) => {
        console.warn(`[dotfiles-harness] checkpoint audit failed: ${error}`)
      })
    await auditQueue
  }

  const updatePressure = async (sessionID, state, model = state.model) => {
    if (!state.usage || !model || ["scheduled", "compacting", "awaiting", "continuing"].includes(state.status)) {
      return
    }
    const usable = usableContext(model, compactionReserved)
    if (!usable) return

    const tokens = tokenCount(state.usage)
    const ratio = tokens / usable
    const level = ratio >= hardRatio ? "hard" : ratio >= softRatio ? "soft" : "none"
    state.model = model
    state.tokens = tokens
    state.usable = usable
    state.ratio = ratio
    state.level = level

    if (level === "none") {
      if (state.auditedLevel !== "none") {
        await audit("eligibility_reset", sessionID, { tokens, usable, ratio })
      }
      state.auditedLevel = "none"
      if (state.status === "eligible" || state.status === "failed") state.status = "ready"
      return
    }

    if (state.status === "ready") state.status = "eligible"
    if (state.status !== "eligible" || state.auditedLevel === level) return
    state.auditedLevel = level
    await audit("checkpoint_eligible", sessionID, { level, tokens, usable, ratio })
  }

  const failCompaction = async (sessionID, state, error) => {
    if (!["scheduled", "starting", "compacting", "awaiting", "compacted"].includes(state.status)) return
    if (state.timeout) clearTimeout(state.timeout)
    state.timeout = undefined
    state.status = "failed"
    state.compactionConfirmed = false
    state.summarizeResolved = false
    await audit("compaction_failed", sessionID, {
      origin: state.origin,
      message: error instanceof Error ? error.message : String(error),
    })
    state.origin = undefined
  }

  const continueSession = (sessionID, state) => {
    if (
      !state.compactionConfirmed ||
      !state.summarizeResolved ||
      !state.postCompactionIdle ||
      state.continuationStarted
    ) return
    if (state.timeout) clearTimeout(state.timeout)
    state.timeout = undefined
    state.continuationStarted = true
    state.continuationActive = false
    state.status = "continuing"
    queueMicrotask(async () => {
      await audit("continuation_started", sessionID, { origin: state.origin })
      try {
        const result = await client.session.prompt({
          path: { id: sessionID },
          query: { directory },
          body: {
            agent: state.agent,
            model: state.modelID
              ? { providerID: state.providerID, modelID: state.modelID }
              : undefined,
            parts: [
              {
                type: "text",
                synthetic: true,
                text: "Continue from the context checkpoint. Proceed with remaining next steps if any; otherwise stop.",
              },
            ],
          },
        })
        if (result?.error || result?.data?.info?.error) {
          throw new Error(String(result?.error ?? result.data.info.error))
        }
        state.status = "ready"
        await audit("continuation_completed", sessionID, { origin: state.origin })
        state.origin = undefined
        await updatePressure(sessionID, state)
      } catch (error) {
        state.status = "failed"
        await audit("continuation_failed", sessionID, {
          origin: state.origin,
          message: error instanceof Error ? error.message : String(error),
        })
        state.origin = undefined
      }
    })
  }

  const startCompaction = async (sessionID, state) => {
    if (state.status !== "starting") return
    state.status = "compacting"
    state.compactionConfirmed = false
    state.summarizeResolved = false
    state.postCompactionIdle = false
    state.continuationStarted = false
    await audit("compaction_started", sessionID, {
      origin: state.origin,
      level: state.level,
      tokens: state.tokens,
      usable: state.usable,
      ratio: state.ratio,
    })
    state.timeout = setTimeout(() => {
      void failCompaction(sessionID, state, new Error("Timed out waiting for compaction completion"))
    }, compactionTimeoutMs)
    state.timeout.unref?.()
    if (!state.providerID || !state.modelID) {
      await failCompaction(sessionID, state, new Error("No completed model usage is available for compaction"))
      return
    }

    try {
      const result = await client.session.summarize({
        path: { id: sessionID },
        query: { directory },
        body: { providerID: state.providerID, modelID: state.modelID },
      })
      if (result?.error || result?.data === false) {
        throw new Error(String(result?.error ?? "OpenCode rejected the compaction request"))
      }
      if (state.status === "failed") return
      state.summarizeResolved = true
      if (!state.compactionConfirmed) {
        state.status = "awaiting"
      }
      continueSession(sessionID, state)
    } catch (error) {
      await failCompaction(sessionID, state, error)
    }
  }

  return {
    suppressesIdle(sessionID) {
      const state = sessions.get(sessionID)
      if (!state) return false
      if (state.status === "continuing") return !state.continuationActive
      return ["scheduled", "starting", "compacting", "awaiting", "compacted"].includes(
        state.status,
      )
    },
    configure(config) {
      compactionReserved = config.compaction?.reserved
    },
    tool: {
      description:
        "Schedule a same-session context checkpoint after the current response becomes idle. Call only after completing and verifying a durable milestone, when the system checkpoint guidance says the session is eligible. Do not call mid-operation.",
      args: {},
      async execute(_args, context) {
        const lineage = await sessionLineage(context.sessionID)
        if (lineage.kind !== "root") return "Context checkpoints are available only to root sessions."

        const state = stateFor(context.sessionID)
        if (state.status !== "eligible") return "Context checkpoint is not currently eligible."
        if (!state.providerID || !state.modelID) return "Context checkpoint has no completed model usage yet."
        const requirement = canaryRequirement(context.sessionID)
        if (requirement) {
          return {
            title: "Canary takeover required",
            output: requirement === "start"
              ? "Run the canary-takeover skill before scheduling this root session's first context checkpoint."
              : "Finish the active canary, sync its terminal evidence, and call canary_takeover_complete before checkpointing.",
            metadata: { canaryRequired: true, requirement },
          }
        }

        state.status = "scheduled"
        state.origin = "automatic"
        state.agent = context.agent
        await audit("checkpoint_scheduled", context.sessionID, {
          origin: state.origin,
          level: state.level,
          tokens: state.tokens,
          usable: state.usable,
          ratio: state.ratio,
        })
        return {
          title: "Context checkpoint queued",
          output: "The checkpoint will run after this response reaches idle.",
          metadata: { level: state.level, ratio: state.ratio },
        }
      },
    },
    async system(input, output) {
      if (!input.sessionID) return
      const lineage = await sessionLineage(input.sessionID)
      if (lineage.kind !== "root") return
      const state = stateFor(input.sessionID)
      state.model = input.model ?? state.model
      await updatePressure(input.sessionID, state)
      if (state.status !== "eligible") return

      const percentage = Math.round(state.ratio * 100)
      const requirement = canaryRequirement(input.sessionID)
      if (requirement === "start") {
        output.system.push(`[canary-takeover]
This root session is using ${percentage}% of its usable model context. Before the first same-session checkpoint, load the canary-takeover skill and execute one bounded live canary without asking the user. If descendants are active, wait and retry preflight at the next safe point.`)
        return
      }
      if (requirement === "complete") {
        output.system.push(`[canary-takeover]
The first-pressure canary is in progress. Finish the successor or aborted audit, record and sync terminal evidence, then call ${canaryCompleteToolName}. Do not call ${checkpointToolName} before canary completion succeeds.`)
        return
      }
      const urgency = state.level === "hard"
        ? "Do not begin another non-trivial milestone before checkpointing."
        : "Finish the current atomic work; checkpoint at the next durable verified milestone."
      output.system.push(`[context-checkpoint]
This root session is using ${percentage}% of its usable model context. ${urgency}
At a safe boundary, call ${checkpointToolName} exactly once. Do not mention context housekeeping to the user. Do not checkpoint while edits, verification, review, or a user decision are incomplete.`)
    },
    async compacting(input, output) {
      const lineage = await sessionLineage(input.sessionID)
      if (lineage.kind !== "root") return
      output.context.push(checkpointCompactionContext)
    },
    async command(input, output) {
      if (input.command !== "checkpoint") return
      const lineage = await sessionLineage(input.sessionID)
      if (lineage.kind !== "root") return

      for (const part of output.parts ?? []) {
        if (part.type === "text") part.synthetic = true
      }

      const state = stateFor(input.sessionID)
      if (["scheduled", "starting", "compacting", "awaiting", "compacted", "continuing"].includes(state.status)) {
        await audit("manual_checkpoint_ignored", input.sessionID, { status: state.status })
        return
      }

      state.status = "scheduled"
      state.origin = "manual"
      state.level = "manual"
      await audit("manual_checkpoint_scheduled", input.sessionID, {
        origin: state.origin,
        tokens: state.tokens,
        usable: state.usable,
        ratio: state.ratio,
      })
    },
    async event(event) {
      if (event.type === "message.updated") {
        const info = event.properties?.info
        if (!info || typeof info.sessionID !== "string") return
        const lineage = await sessionLineage(info.sessionID)
        if (lineage.kind !== "root") return
        const state = stateFor(info.sessionID)
        if (state.status === "continuing" && info.role === "assistant" && !info.summary) {
          state.continuationActive = true
        }

        if (info.role === "user") {
          if (state.status === "failed") {
            state.status = "ready"
            await audit("checkpoint_rearmed", info.sessionID)
            await updatePressure(info.sessionID, state)
          }
          return
        }
        if (info.role !== "assistant" || info.summary || !info.finish || !info.tokens) return
        const usageKey = `${info.id}:${tokenCount(info.tokens)}`
        if (state.usageKey === usageKey) return
        state.usageKey = usageKey
        state.usage = info.tokens
        state.providerID = info.providerID
        state.modelID = info.modelID
        state.agent = info.agent ?? info.mode ?? state.agent
        await updatePressure(info.sessionID, state)
        return
      }

      if (event.type === "session.idle") {
        const sessionID = event.properties?.sessionID
        const state = sessions.get(sessionID)
        if (!state) return
        if (state.status === "scheduled") {
          state.status = "starting"
          queueMicrotask(() => {
            void startCompaction(sessionID, state)
          })
          return
        }
        if (state.status === "compacted") {
          state.postCompactionIdle = true
          continueSession(sessionID, state)
        }
        return
      }

      if (event.type === "session.status") {
        const sessionID = event.properties?.sessionID
        const state = sessions.get(sessionID)
        const status =
          typeof event.properties?.status === "string"
            ? event.properties.status
            : event.properties?.status?.type
        if (state?.status === "continuing" && ["busy", "retry"].includes(status)) {
          state.continuationActive = true
        }
        return
      }

      if (event.type === "session.compacted") {
        const sessionID = event.properties?.sessionID
        if (typeof sessionID !== "string") return
        const state = stateFor(sessionID)
        const requested = ["compacting", "awaiting"].includes(state.status)
        state.compactionConfirmed = true
        state.usage = undefined
        state.usageKey = undefined
        state.level = "none"
        state.auditedLevel = "none"
        state.status = requested ? "compacted" : "ready"
        await audit(requested ? "compaction_succeeded" : "native_compaction_observed", sessionID, {
          origin: state.origin,
        })
        if (requested) {
          continueSession(sessionID, state)
        } else {
          state.origin = undefined
        }
        return
      }

      if (event.type === "session.error") {
        const sessionID = event.properties?.sessionID
        const state = sessions.get(sessionID)
        if (state) await failCompaction(sessionID, state, event.properties?.error ?? "Session error")
        return
      }

      if (event.type === "session.deleted") {
        const sessionID = event.properties?.info?.id
        if (typeof sessionID === "string") sessions.delete(sessionID)
      }
    },
  }
}

const invokesLavish = (command) => {
  return command.includes("lavish-axi")
}

export const DotfilesHarnessPlugin = async ({ client, directory }, options = {}) => {
  const source = await realpath(fileURLToPath(import.meta.url))
  const dotfiles = dirname(dirname(dirname(source)))
  const home = Bun.env.HOME ?? ""
  const configHome = Bun.env.XDG_CONFIG_HOME ?? join(home, ".config")
  const stateHome = Bun.env.XDG_STATE_HOME
  const maturity = Bun.env.AGENT_MATURITY_HOME ?? join(home, "agent-maturity")
  const scopePrompt = join(maturity, "scripts/scope-gate-userpromptsubmit.sh")
  const scopeGate = join(maturity, "scripts/scope-gate-pretooluse.sh")
  const hooks =
    typeof options.hooksDir === "string" ? options.hooksDir : join(dotfiles, "claude/hooks")
  const rootSession = {}
  const parentBySession = new Map()
  const rootSessions = new Set()
  const sessionsByID = new Map()

  const rememberSession = (session) => {
    if (typeof session?.id !== "string") return
    sessionsByID.set(session.id, { ...sessionsByID.get(session.id), ...session })
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
  const syncHerdrTitle = createHerdrTitleSync(directory, rootSession)
  const syncHerdrSubagents = createHerdrSubagentSync({ rootSession, sessionLineage })
  const activeDescendants = createActiveDescendantSync({ sessionLineage })
  const canaryPreflight = await createCanaryPreflight({
    client,
    directory,
    home,
    maturity,
    stateHome,
    sessionLineage,
  })
  const checkpoints = createCheckpointAutomation({
    client,
    directory,
    home,
    stateHome,
    sessionLineage,
    canaryRequirement: (sessionID) => canaryPreflight.requirement(sessionID),
  })
  const slackNotifications = createSlackNotificationSync({
    sessionLineage,
    sessionInfo: (sessionID) => sessionsByID.get(sessionID) ?? { directory },
    suppressIdle: (sessionID) =>
      checkpoints.suppressesIdle(sessionID) || activeDescendants.hasActive(sessionID),
    notify:
      typeof options.slackNotify === "function" ? options.slackNotify : createSlackSender(home),
    permissionDelayMs:
      typeof options.slackPermissionDelayMs === "number"
        ? options.slackPermissionDelayMs
        : undefined,
  })
  const handleEvent = async (input) => {
    if (input.event.type === "session.deleted") {
      await syncHerdrSubagents(input)
      await activeDescendants.handleEvent(input)
      await syncHerdrTitle(input)
      await checkpoints.event(input.event)
      await canaryPreflight.event(input.event)
      const sessionID = sessionIDFromEvent(input)
      if (sessionID) {
        parentBySession.delete(sessionID)
        rootSessions.delete(sessionID)
        sessionsByID.delete(sessionID)
      }
      return
    }
    await syncHerdrTitle(input)
    await syncHerdrSubagents(input)
    await activeDescendants.handleEvent(input)
    await checkpoints.event(input.event)
  }
  let eventQueue = Promise.resolve()
  let notificationQueue = Promise.resolve()
  const enqueueEvent = (operation) => {
    const pending = eventQueue.then(operation)
    eventQueue = pending.catch((error) => {
      console.warn(`[dotfiles-harness] event sync failed: ${error}`)
    })
    return pending
  }
  const enqueueNotification = (operation) => {
    const pending = notificationQueue.then(operation)
    notificationQueue = pending.catch((error) => {
      console.warn(`[dotfiles-harness] notification state sync failed: ${error}`)
    })
    return pending
  }

  return {
    "chat.message": ({ sessionID }) =>
      enqueueNotification(() => slackNotifications.markWorking(sessionID)),
    event: (input) => {
      if (input.event.type === "session.created" || input.event.type === "session.updated") {
        rememberSession(input.event.properties?.info)
      }
      if (input.event.type === "session.deleted") {
        const notification = enqueueNotification(() => slackNotifications.handleEvent(input))
        return enqueueEvent(async () => {
          await notification
          await handleEvent(input)
        })
      }
      const eventSync = enqueueEvent(() => handleEvent(input))
      void enqueueNotification(async () => {
        await eventSync
        await slackNotifications.handleEvent(input)
      })
      return eventSync
    },
    config: async (config) => {
      checkpoints.configure(config)
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
      await checkpoints.system(input, output)
    },
    "experimental.session.compacting": async (input, output) => {
      await checkpoints.compacting(input, output)
      const lineage = await sessionLineage(input.sessionID)
      if (lineage.kind !== "root") return
      const result = await runHook(scopePrompt, { session_id: input.sessionID })
      if (result.stdout.trim()) output.context.push(result.stdout.trim())
    },
    "command.execute.before": checkpoints.command,
    tool: {
      [checkpointToolName]: checkpoints.tool,
      [canaryPreflightToolName]: canaryPreflight.preflightTool,
      [canaryCompleteToolName]: canaryPreflight.completeTool,
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
