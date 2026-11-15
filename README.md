# EMP Escape: $0 Test Slice (Unity 6 + Ink)

AI agents: read `AGENTS.md` (and `CLAUDE.md` for Claude Code) before working here.

Chapter 1 "The Event", one scene: tap-to-move, hotspots (Look/Use/Talk), fixed camera cuts,
a timed dialogue choice, a "Ray will remember that" flag, and a mash quick-time event whose
fail branch pays off that flag. Placeholder art is built from primitives. No paid assets.

## 1. Create the project
1. Unity Hub > Installs > Install Editor > Unity 6 LTS. Tick **iOS Build Support**.
2. Unity Hub > New project > **Universal 3D** template.
   - Project name: `unity-game`
   - Location: `/Users/bruce.frick/Desktop`
   - If Hub refuses because `unity-game` already exists, delete the empty folder and retry.

## 2. Install packages first (before copying scripts, or Unity opens in Safe Mode)
Window > Package Manager:
1. **+ > Install package from git URL**
   `https://github.com/inkle/ink-unity-integration.git#upm`
2. **Unity Registry > AI Navigation > Install**
3. Confirm **Input System** is installed (it is by default in Unity 6 templates).

## 3. Copy the game files in
```
unzip ~/Downloads/emp-escape-slice.zip -d /Users/bruce.frick/Desktop/unity-game
```
That puts everything at `unity-game/Assets/EMPEscape/`. Switch back to Unity and let it compile.
Single-click `Assets/EMPEscape/Ink/chapter1_slice.ink`; the Inspector should show "Master File" with a "Last compile" time.
If it shows nothing Ink-specific, right-click the file > **Reimport**.

## 4. Build the scene and play
Menu bar: **EMP Escape > Build Test Slice Scene**, then press **Play**.

Controls (mouse in Editor, touch on iPhone):
- Tap ground: walk
- Tap a yellow dot or object: Look / Use / Talk menu
- Tap: advance dialogue
- Choices: tap one before the bar runs out (timeout = "Say nothing")
- QTE: mash the red circle

Try both paths: help Ray vs. brush him off, then fail the QTE on purpose.

## 5. Run it on your iPhone (free Apple ID is enough)
1. File > Build Profiles > iOS > **Switch Platform** > **Build**. Pick an output folder.
2. Open `Unity-iPhone.xcodeproj` in Xcode.
3. Target **Unity-iPhone** > Signing & Capabilities: Team = your Apple ID (Personal Team).
   Change the bundle ID if Xcode says it's taken.
4. Plug in the iPhone, select it, press Run.
5. On the iPhone, the first time: Settings > Privacy & Security > **Developer Mode** on,
   then Settings > General > VPN & Device Management > trust your developer certificate.
Free-account installs expire after 7 days; rebuild to refresh.

## Editing the story
All dialogue lives in `Assets/EMPEscape/Ink/chapter1_slice.ink`. Edit it in Unity or in
inkle's free **Inky** editor. Unity recompiles on save.

| Write this in Ink | What the game does |
|---|---|
| `Ray: Some line.` | Shows "Ray" as the speaker |
| `# cam: ray_close` | Hard cut to that camera anchor (children of `CameraAnchors`) |
| `# timer: 7` on the last line before choices | Timed choice; the **last** choice is picked on timeout |
| `# remember: Ray will remember that.` | Top-left toast |
| `# qte: tap 1.5` / `mash 3 8` / `hold 3 1.5` | QTE, then picks the `[success]` or `[fail]` choice |
| `# end` | End screen with Restart after the knot finishes |

Hotspots call knots by name (set on each object's **Hotspot** component: Look/Use/Talk knot).

## Files
| File | Job |
|---|---|
| `Scripts/PlayerController.cs` | Tap-to-move on the NavMesh, opens hotspot menus |
| `Scripts/Hotspot.cs` | Tappable object; walks over, then runs an Ink knot |
| `Scripts/HotspotMenu.cs` | Yellow markers + Look/Use/Talk menu |
| `Scripts/StoryDirector.cs` | Runs Ink, handles tags, choices, QTE branching |
| `Scripts/DialogueUI.cs` | Subtitles, timed choices, remember toast, end screen |
| `Scripts/QTEController.cs`, `QTEPrompt.cs`, `QTESpec.cs` | Quick-time events |
| `Scripts/CameraDirector.cs`, `CameraZone.cs` | Fixed cameras, zone cuts, story cuts |
| `Scripts/GameUI.cs`, `UIFactory.cs`, `SafeArea.cs` | Builds the HUD in code, iPhone safe area |
| `Scripts/GameInput.cs` | Mouse/touch taps, input lock during scenes |
| `Editor/SliceSceneBuilder.cs` | Builds the whole test scene from primitives |
