using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem.UI;
using UnityEngine.UI;

namespace EMPEscape
{
    /// <summary>Creates the whole HUD at runtime and hands out its parts.</summary>
    [DefaultExecutionOrder(-100)]
    public class GameUI : MonoBehaviour
    {
        public static GameUI Instance { get; private set; }

        public DialogueUI Dialogue { get; private set; }
        public QTEController QTE { get; private set; }
        public HotspotMenu HotspotMenu { get; private set; }
        public JoystickUI Joystick { get; private set; }
        public PhoneUI Phone { get; private set; }
        public DecisionsUI Decisions { get; private set; }

        Text weaponLabel;

        void Awake()
        {
            Instance = this;
            GameInput.ResetLocks();
            EnsureEventSystem();

            var canvas = UIFactory.CreateCanvas("GameCanvas", transform);

            // Full-screen (not safe-area) so the stick sits exactly under the thumb. Built first so it draws behind the HUD.
            Joystick = gameObject.AddComponent<JoystickUI>();
            Joystick.Build((RectTransform)canvas.transform);
            var safe = UIFactory.NewRect("SafeArea", canvas.transform).Stretch();
            safe.gameObject.AddComponent<SafeArea>();

            HotspotMenu = gameObject.AddComponent<HotspotMenu>();
            HotspotMenu.Build(safe);

            weaponLabel = UIFactory.Label("Weapon", safe, 32, TextAnchor.UpperRight, new Color(1f, 0.85f, 0.5f));
            weaponLabel.fontStyle = FontStyle.Bold;
            weaponLabel.rectTransform.Anchor(new Vector2(0.5f, 1f), new Vector2(1f, 1f), new Vector2(0f, -80f), new Vector2(-30f, -24f));
            weaponLabel.text = "";

            Dialogue = gameObject.AddComponent<DialogueUI>();
            Dialogue.Build(safe);

            QTE = gameObject.AddComponent<QTEController>();
            QTE.Build(safe);

            Phone = gameObject.AddComponent<PhoneUI>();
            Phone.Build(safe);

            Decisions = gameObject.AddComponent<DecisionsUI>();
            Decisions.Build(safe);

            gameObject.AddComponent<HudUI>().Build(safe, Phone, Decisions);
        }

        /// <summary>Top-right "HOLDING: BAT" label. Empty hides it.</summary>
        public void SetWeapon(string weapon) =>
            weaponLabel.text = string.IsNullOrEmpty(weapon) ? "" : "HOLDING: " + weapon.ToUpperInvariant();

        static void EnsureEventSystem()
        {
            if (FindFirstObjectByType<EventSystem>() != null) return;
            var go = new GameObject("EventSystem", typeof(EventSystem));
            go.AddComponent<InputSystemUIInputModule>().AssignDefaultActions();
        }
    }
}
