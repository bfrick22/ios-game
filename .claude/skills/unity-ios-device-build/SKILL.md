---
name: unity-ios-device-build
description: Build EMP Escape from Unity to the owner's iPhone with Xcode and a free Apple ID - Build Profiles, Xcode signing, Developer Mode, trust, rebuild with Append, and fixes for common errors. Load for any iOS build, signing, or device-install task.
---

# Build to iPhone (free Apple ID)

Agents can't click through Unity or Xcode. Give the owner these steps and ask for exact error text.
The full walkthrough is the Claude Doc "EMP Escape: Run the Test Slice on Your iPhone".

## Project facts
- Company Name `Fritana`, Product Name `EMP Escape`, Version `0.1.0`.
- Xcode output folder: `ios-game/` in the project root (generated; never edit by hand).
- Orientation is landscape (set by `SliceSceneBuilder`).

## One-time setup
1. **iOS module:** if iOS isn't listed in **File > Build Profiles**, quit Unity, then Unity Hub > Installs > Unity 6.6 > ⚙ > **Add modules** > iOS Build Support.
2. **File > Build Profiles > iOS > Switch Platform.** Wait for importing and compiling to finish (spinner bottom-right) before building.
3. **Player settings:** **Edit > Project Settings > Player**. The iOS tab is the **Apple logo** (middle tab). Bundle Identifier is under **Other Settings > Identification**.
4. **Xcode account:** Xcode > Settings > Accounts > + > Apple ID.
5. **iPhone:** plug in, tap **Trust**, then Settings > Privacy & Security > **Developer Mode** On (appears only after connecting to Xcode), restart.

## Each build
1. Unity: **File > Build Profiles > Build** into `ios-game/`. On rebuilds choose **Append** (keeps Xcode signing).
2. Open `ios-game/Unity-iPhone.xcodeproj`.
3. Select the **connected iPhone** as the run destination (not "Any iOS Device").
4. Project navigator (⌘1) > blue **Unity-iPhone** project > TARGETS **Unity-iPhone** > **Signing & Capabilities** tab: **Automatically manage signing** on, Team = owner's **(Personal Team)**.
5. Run (⌘R). First launch: iPhone Settings > General > VPN & Device Management > Developer App > **Trust**.

## Errors seen and fixes
| Error | Fix |
|---|---|
| iOS not listed in Build Profiles | Add iOS Build Support module via Unity Hub |
| "Cannot build player while editor is importing assets or compiling scripts" | Wait for the spinner to stop; fix any red Console errors; then Build |
| "Unity-iPhone requires a provisioning profile" | Select the connected iPhone as destination, tick Automatically manage signing, pick the Personal Team |
| Can't find Signing & Capabilities | It's a tab in the middle pane after selecting the blue project and the Unity-iPhone target (step 4) |
| Bundle identifier not available | Make it more unique on the Signing & Capabilities tab |
| "Untrusted Developer" on launch | Trust the developer app on the iPhone (see step 5) |
| App stops opening after 7 days | Free-account limit. Plug in and Run from Xcode again |
| "Maximum number of apps for free development profiles" | Delete other sideloaded test apps |
Add new errors and fixes to this table when they come up.
