using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem.UI;

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

            Dialogue = gameObject.AddComponent<DialogueUI>();
            Dialogue.Build(safe);

            QTE = gameObject.AddComponent<QTEController>();
            QTE.Build(safe);
        }

        static void EnsureEventSystem()
        {
            if (FindFirstObjectByType<EventSystem>() != null) return;
            var go = new GameObject("EventSystem", typeof(EventSystem));
            go.AddComponent<InputSystemUIInputModule>().AssignDefaultActions();
        }
    }
}
