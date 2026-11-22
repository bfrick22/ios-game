using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace EMPEscape
{
    /// <summary>
    /// Runs one quick-time event and reports success or failure.
    ///   tap / mash / hold: an on-screen button.
    ///   shoot: drag anywhere to move the reticle, lift your finger to fire. Hit every ShootTarget in the
    ///          group before time or rounds run out (rounds = targets + 2).
    ///   swing: swipe in the arrow's direction for each swing. The held weapon sets how long a swipe must
    ///          be (bat: long, knife and fists: short). One wrong or missed swipe fails.
    /// </summary>
    public class QTEController : MonoBehaviour
    {
        const int MaxMarkers = 8;
        const int SpareRounds = 2;
        static readonly Vector2[] SwipeDirections = { Vector2.right, Vector2.up, Vector2.left, Vector2.down };

        [Header("Shoot")]
        [Tooltip("How close the reticle must be to a target, as a fraction of screen height.")]
        public float hitRadius = 0.06f;
        [Tooltip("Reticle sway, as a fraction of screen height. 0 turns it off.")]
        public float sway = 0.015f;

        [Header("Swing (shortest swipe that counts, as a fraction of screen height)")]
        public float knifeSwipe = 0.08f;
        public float batSwipe = 0.16f;
        public float fistSwipe = 0.08f;
        [Tooltip("How far off the arrow's direction a swipe may be, in degrees.")]
        public float swipeTolerance = 45f;

        RectTransform root;
        Image dim;
        Image timeFill;
        Text hintLabel;
        Text resultLabel;

        RectTransform buttonGroup;
        RectTransform button;
        QTEPrompt prompt;
        Text buttonLabel;
        Image ring;
        Image progress;

        RectTransform shootGroup;
        RectTransform reticle;
        Image reticleImage;
        Text shootInfo;
        Image flash;
        readonly List<RectTransform> markers = new List<RectTransform>();

        RectTransform swingGroup;
        RectTransform arrow;
        Image arrowImage;
        Text swingLabel;

        public void Build(RectTransform parent)
        {
            root = UIFactory.NewRect("QTE", parent).Stretch();

            dim = UIFactory.Panel("Dim", root, new Color(0f, 0f, 0f, 0.35f));
            dim.rectTransform.Stretch();
            dim.raycastTarget = false;

            var timeBack = UIFactory.Panel("TimeBar", root, new Color(1f, 1f, 1f, 0.2f));
            timeBack.raycastTarget = false;
            timeBack.rectTransform.Anchor(new Vector2(0.3f, 1f), new Vector2(0.7f, 1f), new Vector2(0f, -48f), new Vector2(0f, -34f));
            timeFill = Filled("Fill", timeBack.rectTransform, new Color(1f, 0.8f, 0.4f, 1f));

            hintLabel = UIFactory.Label("Hint", root, 34, TextAnchor.UpperCenter, Color.white);
            hintLabel.rectTransform.Anchor(new Vector2(0f, 1f), new Vector2(1f, 1f), new Vector2(0f, -130f), new Vector2(0f, -66f));

            BuildButton();
            BuildShoot();
            BuildSwing();

            flash = UIFactory.Panel("Flash", root, new Color(1f, 0.95f, 0.8f, 0f));
            flash.rectTransform.Stretch();
            flash.raycastTarget = false;

            resultLabel = UIFactory.Label("Result", root, 72, TextAnchor.MiddleCenter, Color.white);
            resultLabel.fontStyle = FontStyle.Bold;
            resultLabel.rectTransform.Center(new Vector2(1000f, 120f)).anchoredPosition = new Vector2(0f, 250f);

            root.gameObject.SetActive(false);
        }

        void BuildButton()
        {
            buttonGroup = UIFactory.NewRect("Button", root).Stretch();

            ring = UIFactory.Panel("Ring", buttonGroup, new Color(1f, 1f, 1f, 0.25f));
            ring.sprite = UIFactory.CircleSprite;
            ring.type = Image.Type.Filled;
            ring.fillMethod = Image.FillMethod.Radial360;
            ring.raycastTarget = false;
            ring.rectTransform.Center(new Vector2(320f, 320f));

            var buttonImage = UIFactory.Panel("Press", buttonGroup, new Color(0.85f, 0.2f, 0.15f, 0.95f));
            buttonImage.sprite = UIFactory.CircleSprite;
            button = buttonImage.rectTransform.Center(new Vector2(240f, 240f));
            prompt = buttonImage.gameObject.AddComponent<QTEPrompt>();

            buttonLabel = UIFactory.Label("Label", button, 44, TextAnchor.MiddleCenter, Color.white);
            buttonLabel.rectTransform.Stretch();
            buttonLabel.fontStyle = FontStyle.Bold;

            var bar = UIFactory.Panel("ProgressBack", buttonGroup, new Color(1f, 1f, 1f, 0.2f));
            bar.raycastTarget = false;
            bar.rectTransform.Center(new Vector2(420f, 18f)).anchoredPosition = new Vector2(0f, -210f);
            progress = Filled("Progress", bar.rectTransform, new Color(1f, 0.85f, 0.3f, 1f));
        }

        void BuildShoot()
        {
            shootGroup = UIFactory.NewRect("Shoot", root).Stretch();
            for (int i = 0; i < MaxMarkers; i++)
            {
                var marker = UIFactory.Panel("Target", shootGroup, new Color(1f, 0.85f, 0.4f, 0.5f));
                marker.sprite = UIFactory.RingSprite;
                marker.raycastTarget = false;
                markers.Add(marker.rectTransform.Center(new Vector2(70f, 70f)));
            }

            reticleImage = UIFactory.Panel("Reticle", shootGroup, Color.white);
            reticleImage.sprite = UIFactory.RingSprite;
            reticleImage.raycastTarget = false;
            reticle = reticleImage.rectTransform.Center(new Vector2(110f, 110f));
            var dot = UIFactory.Panel("Dot", reticle, Color.white);
            dot.sprite = UIFactory.CircleSprite;
            dot.raycastTarget = false;
            dot.rectTransform.Center(new Vector2(14f, 14f));

            shootInfo = UIFactory.Label("Info", shootGroup, 36, TextAnchor.LowerCenter, Color.white);
            shootInfo.fontStyle = FontStyle.Bold;
            shootInfo.rectTransform.Anchor(Vector2.zero, new Vector2(1f, 0f), new Vector2(0f, 40f), new Vector2(0f, 100f));
        }

        void BuildSwing()
        {
            swingGroup = UIFactory.NewRect("Swing", root).Stretch();
            arrowImage = UIFactory.Panel("Arrow", swingGroup, Color.white);
            arrowImage.sprite = UIFactory.ArrowSprite;
            arrowImage.raycastTarget = false;
            arrow = arrowImage.rectTransform.Center(new Vector2(300f, 300f));

            swingLabel = UIFactory.Label("Weapon", swingGroup, 40, TextAnchor.MiddleCenter, new Color(1f, 0.8f, 0.4f));
            swingLabel.fontStyle = FontStyle.Bold;
            swingLabel.rectTransform.Center(new Vector2(800f, 60f)).anchoredPosition = new Vector2(0f, -220f);
        }

        public IEnumerator Run(QTESpec spec, Action<bool> onDone)
        {
            bool success = false;
            Action<bool> report = result => success = result;
            resultLabel.text = "";
            timeFill.fillAmount = 1f;
            root.gameObject.SetActive(true);
            yield return null; // the tap that dismissed the last line must not count (or fire a shot)

            switch (spec.type)
            {
                case QTEType.Shoot: yield return RunShoot(spec, report); break;
                case QTEType.Swing: yield return RunSwing(spec, report); break;
                default: yield return RunButton(spec, report); break;
            }

            resultLabel.text = success ? "GOT IT" : "MISSED";
            resultLabel.color = success ? new Color(0.6f, 1f, 0.6f) : new Color(1f, 0.45f, 0.4f);
            AudioDirector.Play(success ? "qte_success" : "qte_fail", 0.7f);
            yield return new WaitForSeconds(0.5f);
            root.gameObject.SetActive(false);
            onDone(success);
        }

        void Show(RectTransform group, float dimAlpha, string hint)
        {
            buttonGroup.gameObject.SetActive(group == buttonGroup);
            shootGroup.gameObject.SetActive(group == shootGroup);
            swingGroup.gameObject.SetActive(group == swingGroup);
            dim.color = new Color(0f, 0f, 0f, dimAlpha);
            hintLabel.text = hint;
        }

        // ---------- tap / mash / hold ----------

        IEnumerator RunButton(QTESpec spec, Action<bool> report)
        {
            Show(buttonGroup, 0.35f, "");
            prompt.ResetState();
            buttonLabel.text = spec.type == QTEType.Mash ? "MASH" : spec.type == QTEType.Hold ? "HOLD" : "TAP";
            progress.transform.parent.gameObject.SetActive(spec.type != QTEType.Tap);
            progress.fillAmount = 0f;
            button.anchoredPosition = new Vector2(UnityEngine.Random.Range(-260f, 260f), UnityEngine.Random.Range(-40f, 120f));
            ring.rectTransform.anchoredPosition = button.anchoredPosition;

            float elapsed = 0f;
            float heldFor = 0f;
            int lastPresses = 0;
            bool success = false;

            while (elapsed < spec.window && !success)
            {
                elapsed += Time.deltaTime;
                ring.fillAmount = timeFill.fillAmount = 1f - elapsed / spec.window;

                switch (spec.type)
                {
                    case QTEType.Tap:
                        success = prompt.PressCount > 0;
                        break;
                    case QTEType.Mash:
                        progress.fillAmount = prompt.PressCount / Mathf.Max(1f, spec.amount);
                        success = prompt.PressCount >= spec.amount;
                        break;
                    case QTEType.Hold:
                        heldFor = prompt.IsHeld ? heldFor + Time.deltaTime : Mathf.Max(0f, heldFor - Time.deltaTime * 2f);
                        progress.fillAmount = heldFor / Mathf.Max(0.01f, spec.amount);
                        success = heldFor >= spec.amount;
                        break;
                }

                // Pulse on each press so mashing feels physical.
                if (prompt.PressCount != lastPresses)
                {
                    lastPresses = prompt.PressCount;
                    button.localScale = Vector3.one * 0.88f;
                    AudioDirector.Play("qte_press", 0.6f, 0.06f);
                }
                button.localScale = Vector3.Lerp(button.localScale, Vector3.one, 12f * Time.deltaTime);
                yield return null;
            }
            report(success);
        }

        // ---------- shoot ----------

        IEnumerator RunShoot(QTESpec spec, Action<bool> report)
        {
            Show(shootGroup, 0.08f, "DRAG TO AIM - LIFT TO FIRE");
            var targets = ShootTarget.InGroup(spec.targetGroup);
            if (targets.Count == 0)
            {
                Debug.LogWarning($"[QTEController] No ShootTargets in group '{spec.targetGroup}'.");
                report(false);
                yield break;
            }
            foreach (var target in targets) target.ResetTarget();

            var cam = Camera.main;
            var player = CharacterActor.Find("Player");
            float unit = Screen.height;
            int rounds = targets.Count + SpareRounds;
            int remaining = targets.Count;
            var aim = new Vector2(Screen.width * 0.5f, Screen.height * 0.45f);
            bool aiming = false;
            Vector2 lastPointer = default;
            float seed = UnityEngine.Random.value * 100f;
            float elapsed = 0f;

            while (elapsed < spec.window && remaining > 0 && rounds > 0)
            {
                elapsed += Time.deltaTime;
                timeFill.fillAmount = 1f - elapsed / spec.window;

                // Relative drag, so the thumb never covers the reticle. Lifting the finger fires.
                bool fire = false;
                if (GameInput.PressedThisFrame(out var down))
                {
                    aiming = true;
                    lastPointer = down;
                }
                if (aiming)
                {
                    if (GameInput.IsPressed(out var position))
                    {
                        aim += position - lastPointer;
                        lastPointer = position;
                    }
                    else
                    {
                        aiming = false;
                        fire = true;
                    }
                }
                aim.x = Mathf.Clamp(aim.x, 0f, Screen.width);
                aim.y = Mathf.Clamp(aim.y, 0f, Screen.height);

                float t = Time.time * 0.7f;
                var drift = new Vector2(Mathf.PerlinNoise(seed, t) - 0.5f, Mathf.PerlinNoise(t, seed + 5f) - 0.5f) * (2f * sway * unit);
                var point = aim + drift;

                ShootTarget over = null;
                float closest = hitRadius * unit;
                int shown = 0;
                foreach (var target in targets)
                {
                    if (target.IsDown) continue;
                    var screen = cam.WorldToScreenPoint(target.AimPosition);
                    if (screen.z <= 0f) continue;
                    if (shown < markers.Count) PlaceOnScreen(markers[shown++], screen);
                    float distance = Vector2.Distance(screen, point);
                    if (distance < closest)
                    {
                        closest = distance;
                        over = target;
                    }
                }
                for (int i = shown; i < markers.Count; i++) markers[i].gameObject.SetActive(false);

                PlaceOnScreen(reticle, point);
                reticleImage.color = over != null ? new Color(1f, 0.3f, 0.25f) : Color.white;

                if (fire)
                {
                    rounds--;
                    StartCoroutine(Flash());
                    AudioDirector.Play("gunshot", 1f, 0.03f);
                    if (player != null) player.Play("shoot");
                    if (over != null)
                    {
                        over.Hit();
                        remaining--;
                    }
                }

                shootInfo.text = $"ROUNDS {rounds}     TARGETS LEFT {remaining}";
                yield return null;
            }

            foreach (var marker in markers) marker.gameObject.SetActive(false);
            report(remaining == 0);
        }

        void PlaceOnScreen(RectTransform element, Vector2 screenPoint)
        {
            element.gameObject.SetActive(true);
            if (RectTransformUtility.ScreenPointToLocalPointInRectangle(shootGroup, screenPoint, null, out var local))
                element.anchoredPosition = local;
        }

        IEnumerator Flash()
        {
            for (float t = 0f; t < 0.12f; t += Time.deltaTime)
            {
                flash.color = new Color(1f, 0.95f, 0.8f, 0.45f * (1f - t / 0.12f));
                yield return null;
            }
            flash.color = new Color(1f, 0.95f, 0.8f, 0f);
        }

        // ---------- swing ----------

        IEnumerator RunSwing(QTESpec spec, Action<bool> report)
        {
            var weapon = WeaponHolder.PlayerWeapon;
            float minSwipe = (weapon == "bat" ? batSwipe : weapon == "knife" ? knifeSwipe : fistSwipe) * Screen.height;
            Show(swingGroup, 0.3f, weapon == "bat" ? "FULL SWIPES IN THE ARROW'S DIRECTION" : "SWIPE IN THE ARROW'S DIRECTION");
            swingLabel.text = weapon == "bat" || weapon == "knife" ? weapon.ToUpperInvariant() : "BARE HANDS";

            var player = CharacterActor.Find("Player");
            var target = CharacterActor.Find(spec.actor);
            int swings = Mathf.Max(1, Mathf.RoundToInt(spec.amount));
            int previous = -1;

            for (int i = 0; i < swings; i++)
            {
                int direction;
                do direction = UnityEngine.Random.Range(0, SwipeDirections.Length); while (direction == previous);
                previous = direction;
                var wanted = SwipeDirections[direction];
                arrow.localEulerAngles = new Vector3(0f, 0f, direction * 90f);
                arrow.localScale = Vector3.one * 0.6f;
                arrowImage.color = Color.white;

                float elapsed = 0f;
                bool tracking = false;
                bool swiped = false;
                bool correct = false;
                Vector2 start = default;

                while (elapsed < spec.window && !swiped)
                {
                    elapsed += Time.deltaTime;
                    timeFill.fillAmount = 1f - elapsed / spec.window;
                    arrow.localScale = Vector3.Lerp(arrow.localScale, Vector3.one, 14f * Time.deltaTime);

                    // A new press is needed for each swing; the swipe counts as soon as it's long enough.
                    if (GameInput.PressedThisFrame(out var down))
                    {
                        tracking = true;
                        start = down;
                    }
                    if (tracking)
                    {
                        if (GameInput.IsPressed(out var position))
                        {
                            var delta = position - start;
                            if (delta.magnitude >= minSwipe)
                            {
                                swiped = true;
                                correct = Vector2.Angle(delta, wanted) <= swipeTolerance;
                            }
                        }
                        else tracking = false;
                    }
                    yield return null;
                }

                if (!correct)
                {
                    if (swiped) AudioDirector.Play("swing_whoosh", 0.8f, 0.08f);
                    arrowImage.color = new Color(1f, 0.4f, 0.35f);
                    yield return new WaitForSeconds(0.25f);
                    report(false);
                    yield break;
                }

                arrowImage.color = new Color(0.55f, 1f, 0.55f);
                if (player != null) player.Play("swing");
                AudioDirector.Play(weapon == "knife" ? "knife_slash" : "swing_whoosh", 0.8f, 0.08f);
                yield return new WaitForSeconds(0.08f);
                AudioDirector.Play("hit_flesh", 0.9f, 0.1f);
                if (target != null) target.Play("flinch");
                yield return new WaitForSeconds(0.15f);
            }
            report(true);
        }

        static Image Filled(string name, RectTransform parent, Color color)
        {
            var image = UIFactory.Panel(name, parent, color);
            image.sprite = UIFactory.WhiteSprite;
            image.type = Image.Type.Filled;
            image.fillMethod = Image.FillMethod.Horizontal;
            image.raycastTarget = false;
            image.rectTransform.Stretch();
            return image;
        }
    }
}
