---
name: connect-mongo
description: Connect MongoDB MCP server to a Vanta environment (staging, prod, local, etc.) with auth checks
argument-hint: "[environment]"
---

# Connect MongoDB MCP Server

Connect the MongoDB MCP server to a Vanta MongoDB environment at runtime using `mcp__mongodb__connect`. No config edits or restarts needed.

## Available Environments

| Environment | AWS Profile | Network |
|---|---|---|
| `dev` / `local` | None | localhost:27017 |
| `dev-global` / `local-global` | None | localhost:27018 |
| `staging` | stagingmongoreadonly | Tailscale (low-trust) |
| `staging-aus` | stagingmongoreadonly-aus | Tailscale (low-trust) |
| `staging-eu` | stagingmongoreadonly-eu | Tailscale (low-trust) |
| `staging-gov` | stagingmongoreadonly-gov | AWS VPN |
| `staging-global` | stagingmongoreadonly | Tailscale (low-trust) |
| `prod` | prodmongoreadonly | Tailscale (high-trust) |
| `prod-aus` | prodmongoreadonly-aus | Tailscale (high-trust) |
| `prod-eu` | prodmongoreadonly-eu | Tailscale (high-trust) |
| `prod-gov` | prodmongoreadonly-gov | AWS VPN |
| `prod-global` | prodmongoreadonly | Tailscale (high-trust) |
| `qa-infra` | qainframongoreadonly | Tailscale (low-trust) |
| `qa-infra-global` | qainframongoreadonly | Tailscale (low-trust) |

## Workflow

When the user invokes `/connect-mongo [environment]`:

1. **Determine environment**: If no argument provided, ask the user which environment they want to connect to. Show the table above.

2. **Resolve connection details**: Map the environment to its URI host:

   **Local environments** (`dev`, `local`, `dev-global`, `local-global`):
   - `dev`/`local`: `mongodb://localhost:27017/obsidian?directConnection=true`
   - `dev-global`/`local-global`: `mongodb://localhost:27018/obsidian?directConnection=true`
   - No auth needed. Skip to step 5 — call `mcp__mongodb__connect` directly.

   **Remote environments** — resolve profile and host:
   - `staging`: profile=`stagingmongoreadonly`, host=`staging-pl-1.84tnf.mongodb.net`
   - `staging-aus`: profile=`stagingmongoreadonly-aus`, host=`staging-aus-pl-0.ffh9p.mongodb.net`
   - `staging-eu`: profile=`stagingmongoreadonly-eu`, host=`staging-eu-pl-0.rfg0b.mongodb.net`
   - `staging-gov`: profile=`stagingmongoreadonly-gov`, host=`staging-gov.b6fge6.mongodbgov.net`
   - `staging-global`: profile=`stagingmongoreadonly`, host=`staging-global-pl-0.okzmh.mongodb.net`
   - `prod`: profile=`prodmongoreadonly`, host=`prod-pl-1.s1uwx.mongodb.net`
   - `prod-aus`: profile=`prodmongoreadonly-aus`, host=`prod-aus-pl-0.f0sew.mongodb.net`
   - `prod-eu`: profile=`prodmongoreadonly-eu`, host=`prod-eu-pl-0.6cgko.mongodb.net`
   - `prod-gov`: profile=`prodmongoreadonly-gov`, host=`prod-gov.ugbjax.mongodbgov.net`
   - `prod-global`: profile=`prodmongoreadonly`, host=`prod-global-pl-0.4ppxj.mongodb.net`
   - `qa-infra`: profile=`qainframongoreadonly`, host=`qa-infra.pdnqk.mongodb.net`
   - `qa-infra-global`: profile=`qainframongoreadonly`, host=`qa-infra-global.byhev.mongodb.net`

3. **Authenticate** (remote environments only):

   **IMPORTANT: Do NOT run aws-vault or tailscale commands yourself.** AWS SSO requires a browser. Tell the user to run the helper script in their terminal:

   ```
   ~/.claude/skills/connect-mongo/setup-mongo-auth.sh <profile>
   ```
   For example: `~/.claude/skills/connect-mongo/setup-mongo-auth.sh stagingmongoreadonly`

   This script handles Tailscale setup and AWS SSO login, then writes temporary credentials to `/tmp/mongo-aws-creds.json`. **Wait for the user to confirm it completed successfully.**

4. **Read credentials** (remote environments only):

   Read the file `/tmp/mongo-aws-creds.json`. It contains:
   ```json
   {
     "accessKeyId": "ASIA...",
     "secretAccessKey": "...",
     "sessionToken": "...",
     "profile": "stagingmongoreadonly"
   }
   ```

5. **Connect**:

   **For local environments**, call `mcp__mongodb__connect` directly:
   ```
   connectionString: mongodb://localhost:27017/obsidian?directConnection=true
   ```

   **For remote environments**, construct the connection string with embedded credentials and call `mcp__mongodb__connect`:
   ```
   mongodb+srv://ACCESS_KEY:URL_ENCODED_SECRET@HOST/obsidian?authMechanism=MONGODB-AWS&authSource=%24external&readPreference=secondary&authMechanismProperties=AWS_SESSION_TOKEN:URL_ENCODED_TOKEN
   ```

   **CRITICAL: URL-encode the secretAccessKey and sessionToken** — they contain characters like `+`, `/`, `=` that break URIs. Use JavaScript-style encoding (replace `+` with `%2B`, `/` with `%2F`, `=` with `%3D`, etc.).

   Example construction (pseudocode):
   ```
   accessKey = creds.accessKeyId
   secret = urlEncode(creds.secretAccessKey)
   token = urlEncode(creds.sessionToken)
   uri = "mongodb+srv://{accessKey}:{secret}@{host}/obsidian?authMechanism=MONGODB-AWS&authSource=%24external&readPreference=secondary&authMechanismProperties=AWS_SESSION_TOKEN:{token}"
   ```

   Call `mcp__mongodb__connect` with this URI. No restart or config edit needed.

6. **Confirm**: After connecting, run a quick `mcp__mongodb__list-databases` or similar to verify the connection works. Tell the user they're connected and that credentials expire in ~1 hour — they can re-run `/connect-mongo` to refresh.

## Troubleshooting

Reference: https://app.getguru.com/card/T6jjXGKc/Connect-to-MongoDB-using-MongoDB-Compass

- **`Server selection timed out after 30000 ms`**: Network issue. Check Tailscale connectivity. User may need to request access via Vanta Atlas (https://vanta.atlassian.net/servicedesk/customer/portal/36/group/28/create/296). Also check for DNS rebind protection — run `dig pl-0-us-east-1.84tnf.mongodb.net +short` to verify.
- **`ForbiddenException: No access`**: User lacks the AWS role. Request at https://vanta.freshservice.com/support/catalog/items/114. After approval: sign out of AWS console (https://vanta.awsapps.com/start#/signout), run `aws-vault clear`, then retry.
- **`InvalidClientTokenId`**: Persisted temporary credentials. Run `aws-vault remove <role>`. Check `aws-vault list` for stale entries.
- **`credentials missing`**: Out-of-date `~/.aws/config` or aws-vault < v7. Update config from https://github.com/VantaInc/obsidian/blob/main/.devcontainer/config_files/aws_config.
- **`Could not find user`**: Stale session. Run `aws-vault clear` and retry.
- **`aws-vault sessions should be nested with care`**: Run `unset AWS_VAULT` first.
- **Credentials expired**: Re-run `setup-mongo-auth.sh <profile>` and then `/connect-mongo` again.

## Notes

- Gov environments use AWS VPN instead of Tailscale — NOT supported in CDEs; user must use local macOS.
- Prod read-write profiles (`prodmongoreadwrite*`) should trigger a strong warning.
- `readPreference=secondary` reduces load on primaries.
- AWS STS credentials last ~1 hour. Re-run the skill to refresh.
- Connection strings use private link (`-pl-`) endpoints — different from old AWS VPN strings.
