using UnityEngine;

namespace EMPEscape
{
    /// <summary>Keeps UI out from under the iPhone notch / Dynamic Island and home indicator.</summary>
    [RequireComponent(typeof(RectTransform))]
    public class SafeArea : MonoBehaviour
    {
        RectTransform rt;
        Rect applied;

        void Awake()
        {
            rt = (RectTransform)transform;
            Apply();
        }

        void Update()
        {
            if (Screen.safeArea != applied) Apply();
        }

        void Apply()
        {
            applied = Screen.safeArea;
            if (Screen.width <= 0 || Screen.height <= 0) return;
            var min = applied.position;
            var max = applied.position + applied.size;
            rt.anchorMin = new Vector2(min.x / Screen.width, min.y / Screen.height);
            rt.anchorMax = new Vector2(max.x / Screen.width, max.y / Screen.height);
            rt.offsetMin = rt.offsetMax = Vector2.zero;
        }
    }
}
