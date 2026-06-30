# Agent Board

Native macOS app plus WidgetKit desktop widget for showing ChatGPT usage from the local Codex login.

## What It Does

- Reads `tokens.access_token` from `~/.codex/auth.json`.
- Calls `GET https://chatgpt.com/backend-api/wham/usage` with `Authorization: Bearer <access_token>`.
- Calls `GET https://chatgpt.com/backend-api/wham/rate-limit-reset-credits` to show reset-credit information.
- Parses the usage response into the email, plan type, 5-hour window, 7-day window, reset-credit count, and reset-credit expiry fields shown by the app and widget.
- Stores only a token-free usage snapshot in the App Group cache.
- Shows the cached snapshot in a macOS desktop widget.
- Runs as a menu bar app. It stays out of the Dock and keeps refreshing the widget cache from the top-right status bar item.

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
8. Use the top-right menu bar item to open the window, refresh manually, reload the widget, enable `Launch at Login`, or quit the app.

## Install Release App

Xcode `Run` starts a Debug build from DerivedData. The app is configured with `LSUIElement=YES`, so it appears only in the top-right menu bar and does not show in the Dock. Pressing `Stop` kills that debug process, so the menu bar refresher also stops. For daily use, install and run the archived app instead:

1. In Xcode, select `Any Mac` or `My Mac`.
2. Choose `Product > Archive`.
3. In Organizer, export the archive as a macOS app.
4. Copy `AgentBoard.app` to `/Applications`.
5. Quit any Xcode-run `Agent Board` process from the menu bar item or Activity Monitor.
6. Start `/Applications/AgentBoard.app` from Finder, Launchpad, or Spotlight.
7. Click `Grant auth.json Access` and select `/Users/fanlv/.codex/auth.json`.
8. Enable `Launch at Login` from the menu bar item if you want background refresh after login.

The Release app is sandboxed and stores its own security-scoped file permission. Grant access once for the installed app even if the Xcode Debug build already worked.

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

The app-level refresh controller reads `~/.codex/auth.json`, refreshes usage on launch, and refreshes every minute while the app process is running. The main window is opened from the top-right menu bar item. Closing the window does not stop this controller; the menu bar item keeps the process alive. Use `Quit Agent Board` from the menu bar item when you want to stop background refreshes.

macOS may still throttle WidgetKit timeline refreshes under power or system policy. The app requests a one-minute cadence, but the system controls the final schedule.

Enable `Launch at Login` from the menu bar item if you want the refresh controller to start automatically after login.

WidgetKit extensions are sandboxed, so the widget intentionally does not depend on directly reading `~/.codex/auth.json`.
