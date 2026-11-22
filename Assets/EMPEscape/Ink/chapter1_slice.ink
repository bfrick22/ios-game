// EMP Escape — Chapter 1 "The Event", test slice.
// Conventions the game reads:
//   Name: text          -> speaker name shown above the line
//   # cam: anchor       -> cut to a camera anchor (name of a child of "CameraAnchors")
//   # timer: seconds    -> on the last line before choices; the LAST choice is picked on timeout
//   # remember: text    -> "X will remember that" toast
//   # qte: tap|mash|hold window amount  -> runs a quick-time event, then picks [success] or [fail]
//   # end               -> shows the end-of-slice screen when this knot finishes
//   # anim: Actor action -> one-shot animation on a CharacterActor, e.g. # anim: Player flinch

VAR has_bag = false
VAR ray_trust = 0
VAR talked_to_ray = false

=== intro ===
The engine died mid-sentence. So did the radio. So did every car on the off-ramp. # cam: intro # ambience: amb_wind # distant: distant_crash
Your phone is black. Your watch is black. Somewhere a car alarm should be screaming. Nothing is.
-> END

=== car_look ===
Dead. Not even the dome light.
-> END

=== car_use ===
{ has_bag:
    You already have the go-bag.
- else:
    ~ has_bag = true
    You pop the trunk by hand and pull out the go-bag. Water, flashlight, first aid kit.
}
-> END

=== van_look ===
A delivery van, back doors hanging open. The boxes inside haven't been touched. Yet.
-> END

=== ray_look ===
{ talked_to_ray:
    Ray keeps glancing toward the city.
- else:
    A man in a delivery uniform, standing very still, staring at his dead phone.
}
-> END

=== ray_talk ===
{ talked_to_ray: -> again }
~ talked_to_ray = true
Ray: You felt that too, right? Everything just stopped. # cam: ray_close
Ray: I've got a daughter across town. I need to get to her. # timer: 7
* ["We should stick together."]
    ~ ray_trust += 1
    Ray: Yeah. Okay. Safer that way. # remember: Ray will remember that.
* ["What do you think happened?"]
    Ray: Not a blackout. Blackouts don't kill cars.
* ["Not my problem."]
    ~ ray_trust -= 1
    Ray: Right. Good luck, then. # remember: Ray will remember that.
* [Say nothing]
    Ray: Okay. Quiet type. Fine.
- -> END

= again
Ray: We should get moving before it gets dark. # cam: ray_close
-> END

=== overpass_look ===
The stairs up to the overpass. From up there you could see how far this goes.
-> END

=== overpass_use ===
A man slides out from between two trucks. His eyes go straight to you. # cam: overpass
Stranger: Hand it over. All of it. # qte: mash 3 7
* [success] -> win
* [fail] -> lose

= win
You shove him back hard. He stumbles, thinks better of it, and runs.
-> ending

= lose
He knocks you flat. # anim: Player flinch
{ ray_trust > 0:
    Ray: Hey! Back off! # remember: Ray had your back.
    The man bolts. Ray pulls you up.
- else:
    { has_bag:
        ~ has_bag = false
        By the time you're on your feet, he's gone. So is your bag.
    - else:
        He finds nothing worth taking and disappears between the trucks.
    }
}
-> ending

= ending
You climb the stairs. From the overpass, every road out of the city is a parking lot. # end
-> END
