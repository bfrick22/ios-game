using System.Collections.Generic;
using UnityEngine;
using UnityEngine.EventSystems;
using UnityEngine.InputSystem;

namespace EMPEscape
{
    /// <summary>Tap/click input (mouse in Editor, touch on device) and the world-input lock used by cutscenes.</summary>
    public static class GameInput
    {
        static int lockCount;
        static readonly List<RaycastResult> uiHits = new List<RaycastResult>();

        public static bool WorldLocked => lockCount > 0;
        public static void Lock() => lockCount++;
        public static void Unlock() => lockCount = Mathf.Max(0, lockCount - 1);
        public static void ResetLocks() => lockCount = 0;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        static void ResetOnLoad() => lockCount = 0;

        public static bool PressedThisFrame(out Vector2 screenPos)
        {
            screenPos = default;
            var pointer = Pointer.current;
            if (pointer == null || !pointer.press.wasPressedThisFrame) return false;
            screenPos = pointer.position.ReadValue();
            return true;
        }

        public static bool IsPressed(out Vector2 screenPos)
        {
            screenPos = default;
            var pointer = Pointer.current;
            if (pointer == null || !pointer.press.isPressed) return false;
            screenPos = pointer.position.ReadValue();
            return true;
        }

        public static bool IsOverUI(Vector2 screenPos)
        {
            var eventSystem = EventSystem.current;
            if (eventSystem == null) return false;
            var data = new PointerEventData(eventSystem) { position = screenPos };
            uiHits.Clear();
            eventSystem.RaycastAll(data, uiHits);
            return uiHits.Count > 0;
        }
    }
}
