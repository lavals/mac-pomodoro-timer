# Focus shortcuts

Pomodoro turns a macOS Focus on when a work session starts and off when it ends, is paused, skipped or reset. It does this by running two shortcuts from the Shortcuts app. You create them once; the names must match exactly:

- `Pomodoro Focus On`
- `Pomodoro Focus Off`

If you use iCloud, the shortcuts sync to your other Macs, so you only need to do this on one of them.

## 1. Pick a Focus

You can use either:

- **Do Not Disturb**, which already exists on every Mac. This is the simplest choice.
- **A custom Focus named "Pomodoro"**, if you want to choose which people and apps may still reach you during work. Create it in **System Settings › Focus › Add Focus… › Custom**, name it `Pomodoro`, and set the allowed people and apps.

Use the same Focus in both shortcuts.

## 2. Create "Pomodoro Focus On"

1. Open the **Shortcuts** app.
2. Choose **File › New Shortcut** (⌘N).
3. Name the shortcut exactly `Pomodoro Focus On` (click the title at the top of the editor to rename it).
4. In the action search field on the right, type `Set Focus` and add the **Set Focus** action.
5. Set the action to **Turn** your Focus (Do Not Disturb or Pomodoro) **On**, and set the duration to **Until Turned Off**.
6. Close the editor window. The shortcut is saved automatically.

## 3. Create "Pomodoro Focus Off"

1. Choose **File › New Shortcut** (⌘N) again.
2. Name it exactly `Pomodoro Focus Off`.
3. Add the **Set Focus** action.
4. Set it to **Turn** the same Focus **Off**.
5. Close the editor window.

## 4. Optional: silence your iPhone too

Open **System Settings › Focus** and turn on **Share Across Devices**. When the Mac turns the Focus on, your iPhone and other devices signed in to the same Apple Account follow it.

## 5. Verify

In Terminal, list your shortcuts:

```sh
shortcuts list
```

Both `Pomodoro Focus On` and `Pomodoro Focus Off` should appear in the output, spelled exactly like that.

Then go back to Pomodoro. If the **Set Up Focus** window is open (the **Set up…** link in the popover opens it while the shortcuts are missing), click **Check again**; it should report that both shortcuts were found. Otherwise just open the popover: the app checks again each time, and the Focus hint disappears once both shortcuts exist. From then on, starting a work session turns the Focus on.

## Troubleshooting

- **"Missing" in Pomodoro although the shortcut exists**: check the name for typos, extra spaces or different capitalization. It must match exactly.
- **The Focus does not change**: run the shortcut once by hand from the Shortcuts app. The first run may ask for permission to change Focus; allow it.
- **You want to stop using Focus**: delete or rename the two shortcuts. The timer keeps working without them.
