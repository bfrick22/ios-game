---
name: phone
description: The player's phone in EMP Escape (techno-prepper premise) - PhoneUI shell and apps (Field-AI preset Q&A, Guide, Comms Wi-Fi chats, Camera with photo subjects, Notes, Flashlight), its Ink variables, the field guide JSON and contacts JSON. Load before changing phone apps, writing field guide entries, adding comms contacts, or adding photographable things.
---

# The phone

Premise: the player is a techno-prepper. The phone survived the EMP in a faraday bag (with a solar panel and a
cold crypto wallet, flavor only). No cell service. It runs a **simulated** small local language model: in fiction
it's an AI; in code every exchange is preset. Never build free-text input or a real LLM for it unless asked.

## Story state (all in Ink, so death-Retry restores it)
| Ink variable | Meaning |
|---|---|
| `has_phone` | Shows the PHONE and LIGHT HUD buttons |
| `phone_battery` | 0-100, shared by all apps. Costs: Field-AI answer 4, photo 2, flashlight 1 per 8 s. Solar panel knot sets it to 100 |
| `pack_<id>` | Loads a field guide data pack (`core` is always loaded) |
| `net_<id>` | Puts a Wi-Fi contact in range (as named in contacts.json) |
Stories without these variables simply have no phone (chapter1_slice).

## Apps (one file each, `PhoneApp` subclasses built by `PhoneUI`)
| App | Content comes from | Notes |
|---|---|---|
| Field-AI (`FieldAIApp`) | `Resources/FieldGuide/fieldguide.json` `question` + `answer` | Tap a preset question; "thinking" dots, then the answer types out. Unloaded packs show NOT LOADED and a "find the data" reply |
| Guide (`GuideApp`) | same file, `title`, `category`, `answer`, `details` | Browse by category, read a topic |
| Comms (`CommsApp`) | `Resources/Phone/contacts.json` + an Ink knot per contact | Ink runs through `IStoryPresenter`: `Name: text` = incoming, `You: text` = outgoing, plain line = system note, choices = reply buttons (write them without quotes). Navigation locks until the knot ends |
| Camera (`CameraApp`) | game screenshot | Full-screen viewfinder, photos for the session. A `PhotoSubject` on screen and within range closes the phone and runs its knot (`darkKnot` when it `needsLight` and the flashlight is off) |
| Notes (`NotesApp`) | Ink `# note: text` | Newest first, unread count on the tile |
| Light | `Flashlight` on the player | Spotlight from the chest; HUD LIGHT button too |

## Field guide entries
```json
{ "id": "burns", "pack": "medical", "category": "First aid", "title": "Burns",
  "question": "How do I treat a burn?", "answer": "Short, spoken-style answer.", "details": "Extra for the Guide." }
```
Packs: `{ "id": "medical", "name": "Field medicine", "howToGet": "Scan a first-aid manual to load it." }`.
Survival and medical content must be accurate and conservative (cite reputable guidance: CDC, EPA, WHO, Red Cross,
Stop the Bleed). Keep answers short enough to read on a phone. No em dashes.

## Adding things
- New data pack: add the pack + entries to the JSON, `VAR pack_<id> = false` in Ink, and a knot that sets it (usually a `PhotoSubject` knot).
- New contact: entry in contacts.json (`flag`, `knot`), `VAR net_<id> = false`, a knot that sets it, and the chat knot (guard repeats with a `<id>_talked` flag).
- New photographable thing: `PhotoSubject` on its root (scene builder `Photographable(...)` helper) and its knot(s).
