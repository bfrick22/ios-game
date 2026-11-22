// EMP Escape — action sandbox. One station per interaction type; not story content.
// Tag reference: .claude/skills/ink-story-authoring/SKILL.md
// The game watches "weapon" and puts that prop in the player's hand: "none", "knife", "bat", "pistol".
// Phone: has_phone shows it, phone_battery is its battery (0-100), pack_<id> loads field guide data,
// net_<id> puts a Wi-Fi contact in range (Resources/Phone/contacts.json).

VAR weapon = "none"
VAR ray_trust = 0
VAR talked_to_ray = false
VAR has_phone = false
VAR phone_battery = 40
VAR pack_medical = false
VAR pack_radio = false
VAR net_basecamp = false
VAR basecamp_talked = false

// Choices saved across play sessions (DecisionLog). Returns the value, or "" if never chosen.
EXTERNAL decided(key)
=== function decided(key) ===
~ return ""

=== intro ===
Action sandbox. Every station tests one kind of interaction. # cam: intro # ambience: amb_wind, amb_birds # distant: distant_shot, distant_crash
Drag anywhere to walk, or tap the ground. Tap a yellow dot to look at, use, or talk to something.
Start with the faraday bag beside you. The sign in front of you lists the rest.
-> END

=== sign_look ===
West side, left to right: the shelf tests mashing, the door tests holding, the jar tests a quick tap.
Ray, near the west fence, tests a timed choice. He remembers your answer, even after you quit.
East side: grab a knife, bat, or pistol from the table. Hit the dummy with a blade or bat, or take the pistol to the range.
The stranger by the north fence is a fight. What you're holding changes it, and losing kills you.
Phone: open the faraday bag. Charge at the solar panel, find Wi-Fi at the relay, photograph the first-aid manual, and find the handbook in the dark shed.
The gate at the back ends the session. CHOICES, bottom right, shows every decision you've made.
-> END

// ---------- Talk: timed choice, "will remember", decisions kept across sessions ----------

=== ray_look ===
{ talked_to_ray:
    Ray keeps checking the gate.
- else:
    A tired man in a delivery uniform, arms crossed.
}
-> END

=== ray_talk ===
{ talked_to_ray: -> again }
~ talked_to_ray = true
~ temp before = decided("ray_answer")
{ before:
- "coming":
    Ray: You again. Last time you said you'd come with me. # cam: ray_close
- "refused":
    Ray: You again. Last time you told me to leave you out of it. # cam: ray_close
- "":
    Ray: You see the smoke over downtown? # cam: ray_close
- else:
    Ray: You again. Still thinking it over? # cam: ray_close
}
Ray: I'm heading out at dark. You coming or not? # timer: 6
* ["I'm coming."]
    ~ ray_trust += 1
    Ray: Good. Two's better than one. # remember: Ray will remember that. # decision: ray_answer = coming, You told Ray you're coming. # note: Ray leaves at dark. You said you'd go with him.
* ["Where are you going?"]
    Ray: North. Away from all of it. # decision: ray_answer = asked, You asked Ray where he's going. # note: Ray is heading north at dark.
* ["Leave me out of it."]
    ~ ray_trust -= 1
    Ray: Suit yourself. # remember: Ray will remember that. # decision: ray_answer = refused, You told Ray to leave you out of it.
* [Say nothing]
    Ray: Fine. Think it over. # decision: ray_answer = silent, You said nothing to Ray.
- -> END

= again
{ ray_trust > 0:
    Ray: We leave at dark. Don't be late. # cam: ray_close
- else:
    Ray: Changed your mind yet? # cam: ray_close
}
-> END

// ---------- Button QTEs ----------

=== shelf_look ===
A metal shelf, tipped over. It could come down on someone.
-> END

=== shelf_use ===
You reach under the shelf and it slides. It pins your legs. # cam: qte_close # sfx: metal_scrape
Push it off! # qte: mash 3 8
* [success] You heave it off and roll clear.
* [fail] It's too heavy. You wait until it shifts, then crawl out.
- -> END

=== door_look ===
A flimsy back door. Something's on the other side.
-> END

=== door_use ===
Something slams into the door from outside. # cam: qte_close # sfx: door_bang
Hold it shut! # qte: hold 3 1.5
* [success] The pounding stops. Footsteps fade.
* [fail] The door bursts in. Nobody there now. # sfx: door_bang
- -> END

=== jar_look ===
A glass jar, balanced on the top shelf.
-> END

=== jar_use ===
You bump the shelf. The jar tips. # cam: qte_close
Catch it! # qte: tap 1.2
* [success] Caught it.
* [fail] It shatters on the ground. # sfx: glass_shatter
- -> END

// ---------- Weapon table ----------

=== knife_look ===
A kitchen knife. Quick cuts, short reach.
-> END

=== knife_use ===
{ weapon == "knife":
    ~ weapon = "none"
    You put the knife back. # cam: table_close # sfx: pickup
- else:
    ~ weapon = "knife"
    You take the knife. # cam: table_close # sfx: pickup
}
-> END

=== bat_look ===
A wooden bat. Slow, heavy swings.
-> END

=== bat_use ===
{ weapon == "bat":
    ~ weapon = "none"
    You put the bat back. # cam: table_close # sfx: pickup
- else:
    ~ weapon = "bat"
    You take the bat. # cam: table_close # sfx: pickup
}
-> END

=== pistol_look ===
A pistol with a few rounds left.
-> END

=== pistol_use ===
{ weapon == "pistol":
    ~ weapon = "none"
    You put the pistol back. # cam: table_close # sfx: pickup
- else:
    ~ weapon = "pistol"
    You take the pistol. # cam: table_close # sfx: pickup
}
-> END

// ---------- Melee: swing QTE ----------

=== dummy_look ===
A training dummy. Hit it with a knife or a bat.
-> END

=== dummy_use ===
{ weapon:
- "knife": -> knife_drill
- "bat": -> bat_drill
- else: -> no_blade
}

= knife_drill
Quick cuts. Follow the arrows. # cam: dummy_close
Go. # qte: swing 0.9 4 Dummy
* [success] Four for four.
* [fail] Too slow. Try again.
- -> END

= bat_drill
Big swings. Use full swipes. # cam: dummy_close
Go. # qte: swing 1.4 2 Dummy
* [success] The dummy rocks on its post.
* [fail] You whiff.
- -> END

= no_blade
You need a knife or a bat from the table.
-> END

// ---------- Shooting: shoot QTE ----------

=== range_look ===
Three targets downrange.
-> END

=== range_use ===
{ weapon != "pistol":
    You need the pistol from the table.
    -> END
}
You take your stance at the bench. # cam: range
Drag to aim. Lift your finger to fire. # qte: shoot 7 range
* [success] All three down.
* [fail] Out of time or out of rounds.
- -> END

// ---------- Fight: a choice first, then the weapon decides the QTE; losing is death + retry ----------

=== stranger_look ===
A man in a torn jacket, watching the weapon table.
-> END

=== stranger_talk ===
Stranger: That gear on the table. I'm taking it. # cam: stranger_close # reset: stranger
Stranger: Don't make this hard. # timer: 5
* [Stand your ground] -> fight
* [Let him take it]
    You step aside. He takes a box of supplies and walks off. # decision: stranger = let_go, You let the stranger take the supplies.
    -> END

= fight
{ weapon:
- "pistol": -> draw
- "knife": -> knife_fight
- "bat": -> bat_fight
- else: -> bare_hands
}

= draw
He lunges. Draw! # qte: shoot 2.5 stranger
* [success] He drops.
    -> won
* [fail] -> lost

= knife_fight
He comes at you. Defend yourself! # qte: swing 1.0 3 Stranger
* [success] He backs off, holding his arm.
    -> won
* [fail] -> lost

= bat_fight
He comes at you. Swing! # qte: swing 1.5 2 Stranger
* [success] He goes down hard.
    -> won
* [fail] -> lost

= bare_hands
He grabs you by the collar. Shove him off! # qte: mash 2.5 9
* [success] You shove him back and he runs.
    -> won
* [fail] -> lost

= won
That was close. # remember: You survived the stranger. # decision: stranger = fought, You fought off the stranger.
-> END

= lost
He's on top of you before you can react. # anim: Player flinch # death: You didn't make it.
-> END

// ---------- Phone: faraday bag ----------

=== bag_look ===
{ has_phone:
    Your faraday bag, open now. The cold wallet's still inside. Worthless until the network comes back, if it ever does.
- else:
    Your faraday bag. Sealed. Whatever the pulse fried out here, it didn't get in there.
}
-> END

=== bag_use ===
{ has_phone:
    The phone and the solar panel are out. The cold wallet stays in the bag.
    -> END
}
You peel the seal open. # sfx: bag_open
~ has_phone = true
Inside: your phone, a folding solar panel, and a cold wallet.
The phone powers on. No service, but everything you loaded onto it is still there. # remember: Phone ready. Tap PHONE to use it. # note: The phone survived the pulse in the faraday bag. Battery is low: charge it at the solar panel.
-> END

// ---------- Phone: solar panel ----------

=== solar_look ===
A folding solar panel, angled at the sun.
-> END

=== solar_use ===
{ not has_phone:
    Nothing to charge yet. Your phone is still in the faraday bag.
    -> END
}
{ phone_battery >= 100:
    The phone is already full.
    -> END
}
You plug the phone into the panel and wait in the sun. # sfx: solar_charge
~ phone_battery = 100
Fully charged. # remember: Phone charged to 100%.
-> END

// ---------- Phone: Wi-Fi relay and Comms ----------

=== relay_look ===
{ net_basecamp:
    The relay's light blinks green. Your phone is on its network.
- else:
    A homemade antenna mast with a small solar panel. Its status light is dark.
}
-> END

=== relay_use ===
{ net_basecamp:
    Your phone is already on BASECAMP-MESH.
    -> END
}
You flip the relay's power switch. Its light turns green. # sfx: device_beep
~ net_basecamp = true
{ has_phone:
    Your phone finds a local network: BASECAMP-MESH. # remember: Wi-Fi found. Open COMMS on your phone. # note: Found a solar Wi-Fi relay in the yard. Network: BASECAMP-MESH.
- else:
    Something nearby could connect to it. Your phone, maybe.
}
-> END

// Played inside the phone's Comms app. "Name: text" arrives as a message, choices are your replies,
// plain lines are system notices.
=== comms_basecamp ===
{ basecamp_talked: -> again }
~ basecamp_talked = true
Connected to BASECAMP-MESH. No internet.
BASECAMP: New device on the mesh. Who's this?
* [A survivor. I found your relay.]
    BASECAMP: Good. That's what the relays are for.
* [Who's asking?]
    BASECAMP: Fair. There are six of us. We run this relay off a solar rig.
- BASECAMP: Are you alone out there?
* [I'm with someone.]
    BASECAMP: Then that's two to feed. Bring what you can carry. # decision: basecamp_alone = no, You told Basecamp you're not alone.
* [I'm alone.]
    BASECAMP: Then stay close to the relay after dark. # decision: basecamp_alone = yes, You told Basecamp you're alone.
* [I'd rather not say.]
    BASECAMP: Smart. Keep it that way with strangers. # decision: basecamp_alone = unsaid, You didn't tell Basecamp whether you're alone.
- BASECAMP: We're north of the river. Follow the relays. # note: Basecamp: six survivors with a solar relay, north of the river. Follow the relays.
-> END

= again
BASECAMP: Still here. Follow the relays north when you're ready.
-> END

// ---------- Phone: Camera loads Field-AI data ----------

=== manual_look ===
A waterlogged first-aid manual. Half the pages are stuck together.
-> END

=== manual_use ===
{
- pack_medical:
    You've already photographed it. Field-AI has the data.
- has_phone:
    Too much to memorize. Open your phone's CAMERA and photograph the pages.
- else:
    Too much to memorize. If only you had a way to copy it.
}
-> END

=== manual_photo ===
{ pack_medical:
    You already have this one.
    -> END
}
You photograph every readable page. Field-AI works through them. # sfx: device_beep
~ pack_medical = true
Field-AI: Field medicine loaded. Ask me about wounds, burns, breaks or dehydration. # remember: Field-AI learned: field medicine. # note: Photographed a first-aid manual. Field-AI now knows field medicine.
-> END

// ---------- Phone: Flashlight (the shed is dark) ----------

=== radio_look ===
A ham radio handbook in a zip bag, on a shelf in the back of the shed.
-> END

=== radio_use ===
{
- pack_radio:
    You've already photographed it.
- has_phone:
    It's too dark in here to read. Turn on the LIGHT, then photograph the pages with the CAMERA.
- else:
    It's too dark in here to read, and too much to memorize anyway.
}
-> END

=== radio_photo ===
{ pack_radio:
    You already have this one.
    -> END
}
In the flashlight beam, you photograph the handbook page by page. # sfx: device_beep
~ pack_radio = true
Field-AI: Radio loaded. Ask me about frequencies, range and making contact. # remember: Field-AI learned: radio. # note: Photographed a radio handbook in the shed. Field-AI now knows radio.
-> END

=== radio_photo_dark ===
The photos come out black. You'll need the flashlight in here. # sfx: device_error
-> END

// ---------- Ambience ----------

=== barrel_look ===
Embers are still glowing in the burn barrel. Someone was here not long ago. # note: Someone was in the yard recently. The burn barrel is still warm.
-> END

// ---------- End screen ----------

=== gate_look ===
The gate out of the yard.
-> END

=== gate_use ===
You push the gate open. # end: End of sandbox
-> END
