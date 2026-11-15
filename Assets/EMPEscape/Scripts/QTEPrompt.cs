using UnityEngine;
using UnityEngine.EventSystems;

namespace EMPEscape
{
    /// <summary>The on-screen QTE button. Counts presses and tracks whether it's held.</summary>
    public class QTEPrompt : MonoBehaviour, IPointerDownHandler, IPointerUpHandler, IPointerExitHandler
    {
        public int PressCount { get; private set; }
        public bool IsHeld { get; private set; }

        public void ResetState()
        {
            PressCount = 0;
            IsHeld = false;
        }

        public void OnPointerDown(PointerEventData eventData)
        {
            PressCount++;
            IsHeld = true;
        }

        public void OnPointerUp(PointerEventData eventData) => IsHeld = false;
        public void OnPointerExit(PointerEventData eventData) => IsHeld = false;
    }
}
