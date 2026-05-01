# README demo screencast

The README has a commented-out `<img>` slot near the Overview section
that points at `images/demo.gif`. Drop a recorded gif at that path and
uncomment the line to ship it.

## Storyboard (10 seconds)

| t      | beat                                              | screen content                            |
| ------ | ------------------------------------------------- | ----------------------------------------- |
| 0.0 s  | Whisky already foregrounded, empty bottle list    | Sidebar + empty content area              |
| 1.0 s  | Click "Create Bottle"                             | Create-bottle sheet appears               |
| 2.0 s  | Type a name (e.g. "Demo")                         | Name field active, cursor visible         |
| 3.5 s  | Pick Windows 10 from the version picker           | Picker open, "Windows 10" highlighted     |
| 5.0 s  | Click "Create"; bottle appears in sidebar         | Sidebar gains the new entry               |
| 6.5 s  | Open bottle, click "Run Program"                  | File picker opens                         |
| 8.0 s  | Pick a tiny demo `.exe` (e.g. `notepad.exe`)      | App launches in its own window            |
| 10.0 s | Notepad visible on screen, text typed in it       | "Hello from Whisky" or similar            |

Aim for **800 px wide**, **15 fps**, **<5 MB** as a gif (or **<2 MB** as
mp4 if you'd rather use HTML5 video — but gif renders inline on GitHub
without the user clicking through). Captions are unnecessary at this
length; the visual flow is self-explanatory.

## Recording recipe

1. Set the Whisky window to a sane size (~1100×750 logical points). The
   recording will be downscaled, so don't go smaller than that or text
   will alias.
2. Start a screen recording with `Cmd+Shift+5` → "Record Selected
   Portion" → drag the selection to match the Whisky window exactly.
3. Run through the storyboard once to warm up. Quit and re-launch
   Whisky so the bottle list is empty for the real take.
4. Record. Save the `.mov` somewhere temporary.
5. Convert to gif:

   ```sh
   brew install gifski
   gifski --width 800 --fps 15 -o images/demo.gif /tmp/whisky-demo.mov
   ```

   If the gif is over 5 MB, drop fps to 12 or width to 720.

6. Verify it loops cleanly and doesn't include any cursor lag in the last
   second (gif loop seams are visible).

## After recording

Edit `README.md`, find the `<!-- TODO: drop demo.gif … -->` block, and
uncomment the `<img>` tag below it. Commit `images/demo.gif` and the
README change in the same commit.

If the gif feels stale six months from now, re-record. Don't ship a
year-old screencast that shows a UI that's since drifted.
