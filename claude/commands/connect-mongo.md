---
name: connect-mongo
description: Connect MongoDB MCP server to a Vanta environment (staging, prod, local, etc.) with auth checks
args: "[environment]"
---

# Connect MongoDB MCP Server

Connect the MongoDB MCP server to a Vanta MongoDB environment. Handles Tailscale routing, AWS auth, and `.mcp.json` configuration.

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

2. **Resolve connection details**: Map the environment to its connection config:

   **Local environments** (`dev`, `local`, `dev-global`, `local-global`):
   - `dev`/`local`: `mongodb://localhost:27017/obsidian?directConnection=true`
   - `dev-global`/`local-global`: `mongodb://localhost:27018/obsidian?directConnection=true`
   - No auth needed. Skip to step 5 with a simple npx config (no aws-vault wrapper).

   **Remote environments** — resolve these variables:
   - `staging`: profile=`stagingmongoreadonly`, uri=`mongodb+srv://staging-pl-1.84tnf.mongodb.net/obsidian`, subnet=`low-trust`
   - `staging-aus`: profile=`stagingmongoreadonly-aus`, uri=`mongodb+srv://staging-aus-pl-0.ffh9p.mongodb.net/obsidian`, subnet=`low-trust`
   - `staging-eu`: profile=`stagingmongoreadonly-eu`, uri=`mongodb+srv://staging-eu-pl-0.rfg0b.mongodb.net/obsidian`, subnet=`low-trust`
   - `staging-gov`: profile=`stagingmongoreadonly-gov`, uri=`mongodb+srv://staging-gov.b6fge6.mongodbgov.net/obsidian`, subnet=`none` (AWS VPN)
   - `staging-global`: profile=`stagingmongoreadonly`, uri=`mongodb+srv://staging-global-pl-0.okzmh.mongodb.net/obsidian`, subnet=`low-trust`
   - `prod`: profile=`prodmongoreadonly`, uri=`mongodb+srv://prod-pl-1.s1uwx.mongodb.net/obsidian`, subnet=`high-trust`
   - `prod-aus`: profile=`prodmongoreadonly-aus`, uri=`mongodb+srv://prod-aus-pl-0.f0sew.mongodb.net/obsidian`, subnet=`high-trust`
   - `prod-eu`: profile=`prodmongoreadonly-eu`, uri=`mongodb+srv://prod-eu-pl-0.6cgko.mongodb.net/obsidian`, subnet=`high-trust`
   - `prod-gov`: profile=`prodmongoreadonly-gov`, uri=`mongodb+srv://prod-gov.ugbjax.mongodbgov.net/obsidian`, subnet=`none` (AWS VPN)
   - `prod-global`: profile=`prodmongoreadonly`, uri=`mongodb+srv://prod-global-pl-0.4ppxj.mongodb.net/obsidian`, subnet=`high-trust`
   - `qa-infra`: profile=`qainframongoreadonly`, uri=`mongodb+srv://qa-infra.pdnqk.mongodb.net/obsidian`, subnet=`low-trust`
   - `qa-infra-global`: profile=`qainframongoreadonly`, uri=`mongodb+srv://qa-infra-global.byhev.mongodb.net/obsidian`, subnet=`low-trust`

3. **Check prerequisites** (remote environments only — run these checks in parallel):

   **a. Tailscale** (skip for gov environments which use AWS VPN):
   ```bash
   tailscale status --self 2>&1
   ```
   - If "Logged out" or not running: Tell user to run `tailscale login` or `sudo tailscale up` and wait for them to confirm.
   - Then check accept-routes:
   ```bash
   tailscale debug prefs 2>&1 | grep RouteAll
   ```
   - If `"RouteAll": false`: Tell user to run `sudo tailscale set --accept-routes` and wait for confirmation.
   - Then verify the subnet router is visible:
   ```bash
   tailscale status --self=false --peers 2>&1 | grep "<subnet>"
   ```
   - If subnet router not found: Warn user that the required subnet router is not visible.

   **b. AWS auth**:
   ```bash
   aws-vault list --profiles 2>&1 | grep "^<profile>$"
   ```
   - If profile not found: Tell user to update `~/.aws/config`.
   - Then test auth:
   ```bash
   aws-vault exec <profile> -- echo "authenticated" 2>&1
   ```
   - If SSO expired or auth fails: Tell user to run `aws-vault login <profile>` and wait for confirmation.

4. **Verify connectivity** (remote environments only):
   ```bash
   aws-vault exec <profile> -- mongosh "<uri>?authSource=%24external&authMechanism=MONGODB-AWS&readPreference=secondary" --eval "db.runCommand({ping:1})" 2>&1
   ```
   - If this fails, diagnose the error and help the user fix it.
   - If this succeeds, proceed to step 5.

5. **Update `.mcp.json`**: Find the `.mcp.json` file in the current project root.

   **For local environments**:
   ```json
   "mongodb": {
     "type": "stdio",
     "command": "npx",
     "args": ["-y", "mongodb-mcp-server", "--connectionString", "<connection-string>"]
   }
   ```

   **For remote environments**:
   ```json
   "mongodb": {
     "type": "stdio",
     "command": "aws-vault",
     "args": [
       "exec", "<profile>", "--",
       "npx", "-y", "mongodb-mcp-server",
       "--connectionString", "<uri>?authSource=%24external&authMechanism=MONGODB-AWS&readPreference=secondary"
     ]
   }
   ```

   Use `jq` or direct file editing to update the mongodb entry. If mongodb doesn't exist in the config, add it.

6. **Instruct user to reload**: Tell the user to reload the VSCode window (or restart Claude Code) for the MCP server to pick up the new config. Remind them that AWS credentials expire (~1 hour) and they'll need to reload again when that happens.

## Troubleshooting

Reference: https://app.getguru.com/card/T6jjXGKc/Connect-to-MongoDB-using-MongoDB-Compass

When diagnosing connection failures, check these common issues:

- **`Server selection timed out after 30000 ms`**: Network issue. Check Tailscale connectivity and that the correct subnet router is visible. User may need to request access to ProdMongoReadOnly group via Vanta Atlas (https://vanta.atlassian.net/servicedesk/customer/portal/36/group/28/create/296). Also check for DNS rebind protection — run `dig pl-0-us-east-1.84tnf.mongodb.net +short` to verify DNS resolution.
- **`AWS request to http://169.254.169.254/latest/api/token timed out`**: The MCP server process didn't pick up AWS credentials. Restart/reload required.
- **`ForbiddenException: No access`**: User lacks the AWS role. Request it at https://vanta.freshservice.com/support/catalog/items/114. After approval: sign out of AWS console (https://vanta.awsapps.com/start#/signout), run `aws-vault clear`, then retry.
- **`InvalidClientTokenId: The security token included in the request is invalid`**: Persisted temporary credentials. Run `aws-vault remove <role>` to clear. Check with `aws-vault list` for anything in the "Credentials" column.
- **`credentials missing`**: Out-of-date `~/.aws/config` or aws-vault < v7. Update config from https://github.com/VantaInc/obsidian/blob/main/.devcontainer/config_files/aws_config and upgrade aws-vault.
- **`Could not find user "arn:aws:sts::..." for db "$external"`**: Stale session. Run `aws-vault clear` and retry.
- **`aws-vault sessions should be nested with care`**: Run `unset AWS_VAULT` first.
- **Forgotten aws-vault keychain password** (macOS): Run `rm ~/Library/Keychains/aws-vault.keychain-db`, then re-run — you'll be prompted for a new password.

### Read/Write Access

Default profiles are read-only. To override for write access:
```bash
# Override the AWS profile for read-write
AWS_PROFILE=stagingmongoreadwrite vanta-mongodb staging
```
Each region has its own read-write role (e.g., `prodmongoreadwrite-eu` for prod-eu). Warn the user strongly when using read-write profiles.

## Notes

- Gov environments use AWS VPN instead of Tailscale — skip Tailscale checks for those. Gov is NOT supported in CDEs as of now; user must use local macOS.
- Prod read-write profiles (`prodmongoreadwrite*`) should trigger a warning.
- The `readPreference=secondary` is used for remote to reduce load on primaries.
- AWS STS credentials injected by aws-vault typically last ~1 hour.
- The connection strings use private link (`-pl-`) endpoints — these are different from the old AWS VPN connection strings.
