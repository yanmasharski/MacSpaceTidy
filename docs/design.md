# MacSpaceTidy — design

> Source of truth for product and design decisions. Decided with the user on 2026-10-13
> in question rounds, from a real cleanup session on a Mac mini with the smallest internal storage.

## Goal

A Mac tool that shows what uses disk space, shows problems, and frees space almost with one button:
**Scan → Optimize**. It deletes safe caches and moves big folders to an external disk behind a symlink.
Open source. Other people have the same problem.

## Product

### Two interfaces, one core

One Swift package:

| Part | What it is |
|---|---|
| `MacSpaceTidyCore` | Scan, catalog, problem checks, delete, move, undo. All logic lives here. |
| App | SwiftUI `.app`. Main product. |
| `mac-space-tidy` | Terminal program: full-screen interface (same layout as the app) and plain `scan` report. No third-party libraries. |

Platform: macOS 14 Sonoma or newer. UI language in v1: English (Russian later via String Catalog).
The app runs without a sandbox (it must clean other apps' folders).

### Main screen

1. **Disk bar.** Used / free from `df` (real numbers), split into labeled category segments.
2. **Problems.** Each problem has one fix button.
3. **List.** Scrollable list of expandable categories. Each item has a checkbox, size bar, risk, and reason.

No treemap or sunburst in v1.

Terminal keys: arrows move, space toggles, Enter expands, `s` scans, `o` optimizes.

### Problems block

| Check | Fix button |
|---|---|
| Link points to an external disk that is not mounted | "Connect the disk" |
| Stray nested link (a link inside a folder with the same name, like `~/Library/Caches/Caches`; it comes from `ln -s` when the target already existed) | "Remove link" (data on the external disk stays) |
| Broken link (Chromium lock files like `SingletonLock` are ignored) | "Remove link" |
| Local Time Machine snapshots hold space | "Delete snapshots" (admin password) |
| Low free space (< 10 % or < 20 GB) | Warning on top: swap may run out |

### One button

- Scan builds a plan. Only **safe** items are checked by default (caches that rebuild themselves).
- Moves and simulator runtimes are in the plan but **not** checked by default.
- "Never touch" paths are not shown as actions at all.
- Optimize shows a confirm window: final list with sizes and a switch **"Move to Trash / Delete now"**.
  Default is Trash. The last choice is remembered. Hint: "Trash frees space only after you empty it".
- Admin paths are always deleted now (they cannot go to the user's Trash). The list says so.
- Admin paths ask for the password with the standard macOS prompt, only when such an item is checked.

### During optimize

- Before each item, check that the owner app (listed in the catalog) is not running.
  If it is, ask to quit it or skip the item.
- Progress per item. Cancel works between items. A move is never cut in the middle.
- At the end: "Freed X GB", measured with `df` before and after, not `du`.
  If Time Machine snapshots hold the space, say it.

### Moves to an external disk

- The user picks one external disk in settings.
- Layout: `<disk>/MacSpaceTidy/<original absolute path>`, for example
  `<disk>/MacSpaceTidy/Users/<name>/.cache/uv`.
- Refuse exFAT and FAT (no permissions, no symlinks). Only APFS and HFS+.
- Warn before a move: the link breaks when the disk is not connected.
- Recipe (from the real session; copy tool changed, see below):
  1. Check that no process uses the folder. Close the owner app.
  2. Copy, do not move: `ditto <src> <dest>`.
  3. Compare a tree summary of both sides (counts, sizes, relative paths).
  4. Summarize the source again. It must match the summary from before the copy.
  5. Swap: `mv <src> <src>.old && ln -s <dest> <src>`.
  6. Check that the link works.
  7. Only then delete `<src>.old`.
- Copy tool: `ditto`, not `rsync`. Since macOS 15 `/usr/bin/rsync` is openrsync, and its `-E`
  (extended attributes) fails. `ditto` keeps hard links, links, permissions, and extended attributes.
- Path names are compared in one Unicode form (NFD): HFS+ disks store "й" decomposed, APFS keeps it as written.
- Moves are allowed only inside the home folder and `/Users/Shared`. Other places are read before external disks connect.
- **Undo ("Move back")** works for any link to an external disk: the tool's own moves and links made by hand.
  Same recipe in reverse. First check there is enough free space on the internal disk.
  The copy on the external disk stays; the result window shows its path. The user deletes it when sure.
- The move journal lives on the internal disk: `~/Library/Application Support/MacSpaceTidy/`.
  The tool never moves itself, its journal, or its settings.

### Move or delete (decided 2026-10-13, round 5)

- Big developer caches have a catalog flag `canMove` (uv, npm, Gradle, NuGet, Bun, DerivedData,
  iOS DeviceSupport, Homebrew cache). Their row has a "Move / Delete" switch.
- Moving is preferred: when an external disk is chosen, these items default to Move. Without a disk they are deleted.
- Small app caches in `~/Library/Caches/*` are delete only: many apps delete and recreate their cache folder,
  which silently replaces the link with a normal folder.

### External disk cleanup

- After the main scan, a slow background scan measures moved folders (sizes and newest change date).
  The scan reads only the targets of known links, caches inside them, and copies from the move journal.
  It never walks the whole external disk (decided 2026-10-13).
- **Size cache** (`~/Library/Application Support/MacSpaceTidy/sizes.json`): sizes of those folders from the
  last scan. The screen shows them at once and marks them as old ("~", orange note "Size from the last scan,
  2 hours ago. Counting again…", a spinner on the category). When the new count finishes, the marks go away.
  A damaged or missing cache file means "no cache": the folders show "measuring…".
- Each external disk with moved folders gets a small bar: moved from this Mac, other data, free.
- Category "Clean on external disk":
  - a moved folder that is a cache (like `~/.cache/uv`): emptied; the folder and link stay;
  - a cache inside a moved folder (like `DerivedData` inside a moved `Xcode`): deleted;
  - a copy that nothing links to (from the move journal, for example after Move back): deleted.
- Moved folders show "Last changed …" as a hint that they may be safe to clean. No action is tied to it.
- Not checked by default: this frees the external disk, not the Mac.

### What gets actions

- Delete or move actions exist **only** for paths in the catalog (known paths with known risk).
- Big unknown folders go to the category "Large, unknown". Info only, no checkbox.
  A manual "Move…" exists for them, with a clear warning.

### How things are deleted

- **Clean means empty.** A cleaned folder keeps existing; only what is inside is deleted
  (decided 2026-10-13). Links to it, its permissions, and its attributes stay. A plain file is deleted.
  Admin paths use `find <path> -mindepth 1 -delete` for the same result.
- The only whole-folder delete: a copy inside `<disk>/MacSpaceTidy/` that nothing links to.
- Normal folders: file operation (Trash or delete now, as the user chose).
- Tool commands only where deleting files by hand is wrong:
  simulator runtimes (`xcrun simctl runtime delete`, with a timeout — it can hang), snapshots (`tmutil`).
- Sizes are always measured on disk (allocated size of the link target).
  Never trust a tool's own size command (`uv cache size` prints 0 through a symlink).

## Catalog (v1, about 25 entries)

Rules are data (`catalog.json`), not code. Starting content:

| Action | Paths |
|---|---|
| Delete, safe (checked) | `~/Library/Caches/*`, `~/Library/Logs/*`, Xcode `DerivedData`, `iOS DeviceSupport`, `~/.cache/uv`, `~/.npm`, `~/.gradle/caches`, `~/.nuget/packages`, `~/.bun/install/cache`, `~/Library/Caches/Homebrew` |
| Delete, admin | `/Library/Developer/CoreSimulator/Caches` |
| Simulator runtimes | One unchecked item per runtime, `xcrun simctl runtime delete` |
| Move | `Application Support/<App>` for Cursor, Claude, JetBrains, Steam, Whisky, Figma; `Xcode/Archives`; `~/.android`; `~/.cocoapods`; `/Users/Shared/Epic Games` (warn: Epic launcher) |
| Clean in the app | `Containers/`, `Group Containers/`, Mail, Messages, Safari |
| Never touch | `Preferences`, `Keychains`, `IdentityServices`, `CloudStorage`, `Biome`, `LaunchAgents`, `LaunchDaemons`, fonts, `/System`, iCloud, the tool and its journal |

## Ideas taken from SpaceGuard (2026-10-13)

[SpaceGuard](https://github.com/mkrn/spaceguard) (MIT, by mkrn) solves a neighbor problem: it deletes developer junk.
What MacSpaceTidy took from it, as ideas (the code is separate):

- Folder sizes with `getattrlistbulk` (`BulkDirectoryReader`). Measured on this Mac: internal scan about 25% faster,
  single folders up to 2.5x faster, the external disk only about 15% faster (it is limited by reading the disk).
  Sizes match the old `fts` walk, which stays in the tests as a reference.
- A longer catalog of known cache locations (about 110 entries).
- `ageMatters`: a cache of one app that changed in the last 2 days is not checked by default.
  Global download caches (npm, Cargo, Gradle) are checked whatever their age.
- Retry with `chmod -R u+w` and `chflags nouchg` for read-only trees (the Go module cache).
- Delete guards: only inside the home folder or `/Users/Shared`, never a folder with `.git`.
- A snapshot mode (`MacSpaceTidyApp --snapshot out.png --demo`), used for the README screenshots and to check the UI
  without a screen. It uses made-up data and never reads or writes real settings.

Not taken yet: git worktree cleaning, a menu-bar watcher with a low-space notification, and reusing sizes of trees
that were quiet for days (the size cache already shows old sizes while it counts again).

## Distribution

- Public GitHub repo `yanmasharski/MacSpaceTidy`, MIT license.
- No paid Apple account. Ad-hoc signed build.
- README has two paths: (1) download the `.zip` from GitHub Releases, first launch via right click → Open;
  (2) build from source: `swift build` for the terminal program, `scripts/build-app.sh` for the app.
  The app is a SwiftPM target packed into a `.app` by that script, so no Xcode project and only the
  command line tools are needed.
- Releases by hand. GitHub Actions later.

## Plan

| Step | Content | Estimate |
|---|---|---|
| 1 | Core + plain `scan` + tests on temp folders | ~4 h |
| 2 | App: bar, list, Scan → Optimize for delete | ~6 h |
| 3 | Move and undo in core and app | ~5 h |
| 4 | Terminal full-screen interface | ~4 h |
| 5 | README, license, first release | ~1 h |

Tests: core logic (catalog, classification, link checks, move and undo) runs on temp folders, never on the
real home folder. Interfaces are checked by hand with a checklist.

## Acceptance criteria

1. `scan` is read-only. It shows the biggest folders and tags each as Delete, Move, Clean in app, or Never touch.
2. Every suggestion shows size, risk, and reason. Freed space is checked with `df`, not only `du`.
3. Move follows the 7-step recipe, with a dry run and an undo.
4. The tool refuses "never touch" paths and SIP paths. It warns about admin paths and boot-time paths.
5. It finds stray nested links, already moved folders, and links to a disk that is not mounted.
6. After each action it shows the real free space gained, from `df`.

## Edge cases

External disk not mounted at login. Disk full during copy. App running during a move. exFAT disk.
Case-insensitive file names. Hard links and APFS clones (size reports). Sandboxed apps in `Containers/`.
Cloud folders (iCloud, Google Drive). Time Machine snapshots holding freed space.
The tool must never move itself or its own config.
