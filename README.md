# MotePad

A native **aarch64 (Apple Silicon) assembly** port of
[TinyRetroPad](https://github.com/plummersSoftwareLLC/TinyRetroPad) — a Notepad-style text editor —
for macOS.

The original is x86 MASM assembly wrapping the Win32 `RICHEDIT50W` control. MotePad is written
entirely in ARM64 assembly (`motepad.s`, no C) and drives **AppKit/Cocoa** through the Objective-C
runtime. It keeps the original's functionality but adopts the macOS look and feel: a global
top-of-screen menu bar, ⌘-based shortcuts, native Open/Save panels, the native find bar, the native
font panel, and the native "document edited" dot in the close button.

It also keeps a retro **in-window menu bar** (File / Edit / Format / View / Help) across the top of
the window — a nod to the original's Windows layout — so you get *both* the native global menu bar
and the classic in-window one. Both drive the same commands.

## Origin & credits

The idea and all its heritage come from
**[TinyRetroPad](https://github.com/plummersSoftwareLLC/TinyRetroPad)** by
[Plummer's Software LLC](https://github.com/plummersSoftwareLLC) — the ~2.5 KB Windows Notepad clone
in x86 assembly. That project has a lovely lineage this port is built on:

- **`tiny.asm`** from **Dave Plummer**'s *HelloAssembly* project — the original size-obsessed,
  minimalist assembly seed.
- **Dave's Tiny Editor (DTE)** by **Matt Power** — extended `tiny.asm` into a working text editor.
- **TinyRetroPad** (Plummer's Software LLC) — grew that into a full Notepad-style editor with menus,
  dialogs, and a status bar.
- **MotePad** (this project) — an independent, from-scratch native **aarch64/macOS** port of that
  same idea.

Full credit for the concept and its byte-golfed heritage belongs to Dave Plummer, Matt Power, and the
TinyRetroPad contributors. MotePad is an homage — it is not affiliated with or endorsed by them.

## Build & run

Requires the Xcode command-line tools (clang + the macOS SDK) on an Apple Silicon Mac.

```sh
./build.sh          # assembles motepad.s, links -framework Cocoa, packages MotePad.app
open MotePad.app    # launch
open -a "$PWD/MotePad.app" somefile.txt   # open a file (exercises application:openFile:)
```

`build.sh` produces `MotePad.app` (a normal double-clickable bundle) and ad-hoc code-signs it.

## Install

Download `MotePad-1.0.pkg` from the
[Releases page](https://github.com/emkey1/MotePad/releases) and double-click it to install MotePad
into `/Applications`. To build the installer yourself: `./package.sh` (produces
`dist/MotePad-1.0.pkg`).

The installer and app are **ad-hoc signed** — not notarized with an Apple Developer ID — so macOS
Gatekeeper will warn that the developer is unidentified. To proceed:

- **Installer:** right-click `MotePad-1.0.pkg` → **Open** → **Open** (or approve it in
  System Settings → Privacy & Security).
- **First launch:** right-click `/Applications/MotePad.app` → **Open** → **Open**.
- Or clear the quarantine flag from a terminal:
  `xattr -dr com.apple.quarantine /Applications/MotePad.app`

## How it works

macOS has no way to build a Cocoa app "from syscalls"; the native, idiomatic path is to call AppKit.
MotePad does that directly from assembly:

- **Objective-C dispatch.** Every UI call is `objc_msgSend(receiver, selector, args…)` — receiver in
  `x0`, selector in `x1`, args in `x2…`/`v0…`. Class and selector pointers are resolved once at
  startup from descriptor tables (`DEFCLS` / `DEFSEL` macros) into cached slots.
- **Runtime-created classes.** The app delegate/controller (`MPController`), the file-drop text view
  (`MPTextView`), and the line-number ruler (`MPRuler`) are built at runtime with
  `objc_allocateClassPair` / `class_addMethod` / `objc_registerClassPair`, using assembly functions as
  the method IMPs (signature `(id self, SEL _cmd, …)`).
- **Responder chain.** Standard editing commands (Cut/Copy/Paste/Delete/Select All/Undo/Redo, Find,
  Print, Page Setup, Show Fonts, About) are wired as first-responder actions with no custom code —
  AppKit routes them to `NSTextView` / `NSApplication` / `NSFontManager`.
- **Apple arm64 ABI details handled:** an `NSRect` (4 doubles) is passed/returned in `v0–v3`, an
  `NSSize`/`NSPoint` in `v0–v1`, an `NSRange` in `x0:x1`; **variadic** args (`NSLog`,
  `stringWithFormat:`) go on the **stack**, not in registers; `v8–v15` are callee-saved and used to
  hold layout coordinates across calls.

## Feature parity (original → MotePad)

| TinyRetroPad | MotePad |
|---|---|
| Rich edit control | `NSTextView` in an `NSScrollView` (plain-text, undo, native find bar) |
| Default font Courier | `NSFont fontWithName:"Courier"` |
| **File:** New / Open / Save / Save As | ⌘N / ⌘O / ⌘S / ⇧⌘S, `NSOpenPanel`/`NSSavePanel`, UTF-8 (MacRoman fallback on load) |
| Page Setup / Print | ⇧⌘P `runPageLayout:` / ⌘P `NSView print:` |
| **Edit:** Undo/Redo, Cut/Copy/Paste/Delete/Select All | ⌘Z/⇧⌘Z, ⌘X/⌘C/⌘V/⌦/⌘A (first responder) |
| Find / Find Next / Replace | ⌘F / ⌘G / ⇧⌘F via the native find bar (`performTextFinderAction:`) |
| Go To (line) | ⌘L modal with a numeric field, then caret jump |
| Time/Date | Insert Date and Time (localized) at the caret, undo-aware |
| **Format:** Word Wrap | toggles container width-tracking + horizontal scroller (on by default) |
| Font… | ⌘T Show Fonts (`NSFontManager`) |
| **View:** Status Bar | Ln/Col bar, updates on caret move, hidden by default (matches original) |
| Line Numbers (optional) | `NSRulerView` subclass drawing logical line numbers in a gutter |
| Right-click context menu | native `NSTextView` context menu |
| Title + unsaved indicator | window title = filename / "Untitled"; unsaved = native edited-dot (`setDocumentEdited:`) + represented URL |
| Drag-and-drop file load | `application:openFile:` (Finder/dock) + `MPTextView` file-drop |
| **Help:** View Help / About | Help menu "MotePad Help"; About in the app menu (standard about panel) |

### Intentional macOS adaptations

- Shortcuts use **⌘** (not Ctrl) and the menu bar is the **global** top-of-screen bar.
- The unsaved-changes indicator is the native **dot in the close button**, not a `*` in the title.
- "Dark Mode" from the original is omitted — macOS themes the app automatically via the system
  appearance (this was a decision made when scoping the port).
- Crinkler byte-golf compression (the original's toolchain) has no macOS equivalent and is out of
  scope; this port targets functional + visual parity, not a byte-count record.

## Verifying without a screen

`motepad.s` has a built-in self-test that constructs the whole UI, then introspects the live AppKit
objects and prints them — so the menu tree, document IO, Ln/Col math, Go-To, and date formatting can
all be checked headlessly:

```sh
MOTEPAD_SELFTEST=1 ./MotePad.app/Contents/MacOS/MotePad   # dump menu bar + run IO/Ln-Col/GoTo/date tests, then exit
MOTEPAD_LINENUMS=1 ./MotePad.app/Contents/MacOS/MotePad    # launch with the line-number gutter on
```

## Files

- `motepad.s` — the entire program in ARM64 assembly.
- `build.sh` — assemble, link, and package `MotePad.app`.
- `Info.plist` — bundle metadata (`NSPrincipalClass=NSApplication`, `.txt` document type).
