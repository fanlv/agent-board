# Agent Board

Native macOS app plus WidgetKit desktop widget for showing ChatGPT usage from the local Codex login.

## What It Does

- Reads `tokens.access_token` from `~/.codex/auth.json`.
- Calls `GET https://chatgpt.com/backend-api/wham/usage` with `Authorization: Bearer <access_token>`.
- Calls `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits` to show reset-credit information.
- Parses the JSON response defensively, extracting likely usage, limit, quota, reset, plan, tier, and message fields.
- Stores only a token-free usage snapshot in the App Group cache.
- Shows the cached snapshot in a macOS desktop widget.

The access token is never written to disk by this app.
Release builds of the main app are sandboxed. Debug builds use a non-sandboxed entitlement file so Xcode can run the app directly without macOS sandbox init crashes. On first run, grant read-only access to `~/.codex/auth.json`; the app stores a security-scoped bookmark, not the token.

## Run

1. Open `AgentBoard.xcodeproj` in Xcode.
2. Select both targets: `AgentBoard` and `AgentBoardWidget`.
3. Set your signing team.
4. Keep or update the App Group ID in both entitlements:

   ```text
   9BQ563P4RA.com.fanlv.AgentBoard
   ```

   For macOS App Sandbox, the App Group must use your Team ID prefix. If you change it, update both entitlements and `AppConfiguration.appGroupIdentifier`.

5. Run the `AgentBoard` app and press `Refresh`.
6. If prompted in the app, click `Grant auth.json Access` and select `~/.codex/auth.json`.
7. Add the `Agent Usage` widget from macOS widget gallery.

## Build Check

For a local compile check without signing:

```bash
xcodebuild -project AgentBoard.xcodeproj \
  -scheme AgentBoard \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Update Behavior

The main app reads `~/.codex/auth.json`, refreshes usage on launch, and refreshes every minute while it is running. The widget reads the token-free snapshot from the App Group cache and asks WidgetKit for a new timeline every minute.

macOS may still throttle WidgetKit timeline refreshes under power or system policy. The app requests a one-minute cadence, but the system controls the final schedule.

WidgetKit extensions are sandboxed, so the widget intentionally does not depend on directly reading `~/.codex/auth.json`.
