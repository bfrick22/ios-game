using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace EMPEscape
{
    /// <summary>Dots over every tappable thing, plus the Look / Use / Talk menu for the tapped one.</summary>
    public class HotspotMenu : MonoBehaviour
    {
        RectTransform area;
        RectTransform menu;
        Text title;
        Button lookButton, useButton, talkButton;
        Hotspot current;
        Camera cam;

        readonly List<Hotspot> hotspots = new List<Hotspot>();
        readonly List<Vector3> markerPoints = new List<Vector3>();
        readonly List<RectTransform> markers = new List<RectTransform>();

        public void Build(RectTransform parent)
        {
            area = UIFactory.NewRect("Hotspots", parent).Stretch();

            var background = UIFactory.Panel("Menu", area, new Color(0f, 0f, 0f, 0.7f));
            menu = background.rectTransform.Center(new Vector2(300f, 300f));
            menu.pivot = new Vector2(0.5f, 0f);
            var layout = background.gameObject.AddComponent<VerticalLayoutGroup>();
            layout.padding = new RectOffset(14, 14, 12, 14);
            layout.spacing = 10f;
            layout.childControlWidth = layout.childControlHeight = true;
            layout.childForceExpandHeight = false;
            var fitter = background.gameObject.AddComponent<ContentSizeFitter>();
            fitter.verticalFit = ContentSizeFitter.FitMode.PreferredSize;

            title = UIFactory.Label("Title", menu, 30, TextAnchor.MiddleCenter, new Color(1f, 0.8f, 0.4f));
            title.gameObject.AddComponent<LayoutElement>().preferredHeight = 44f;

            lookButton = VerbButton("Look", HotspotVerb.Look);
            useButton = VerbButton("Use", HotspotVerb.Use);
            talkButton = VerbButton("Talk", HotspotVerb.Talk);

            menu.gameObject.SetActive(false);
        }

        Button VerbButton(string label, HotspotVerb verb)
        {
            var button = UIFactory.MakeButton(label, menu, 34, out var text);
            text.text = label;
            button.gameObject.AddComponent<LayoutElement>().preferredHeight = 72f;
            button.onClick.AddListener(() => Choose(verb));
            return button;
        }

        void Start()
        {
            cam = Camera.main;
            hotspots.AddRange(FindObjectsByType<Hotspot>(FindObjectsSortMode.None));
            foreach (var hotspot in hotspots)
            {
                var collider = hotspot.GetComponentInChildren<Collider>();
                var point = collider != null
                    ? collider.bounds.center + Vector3.up * (collider.bounds.extents.y + 0.35f)
                    : hotspot.transform.position + Vector3.up;
                markerPoints.Add(point);

                var marker = UIFactory.Panel("Marker", area, new Color(1f, 0.85f, 0.4f, 0.9f));
                marker.sprite = UIFactory.CircleSprite;
                marker.raycastTarget = false;
                markers.Add(marker.rectTransform.Center(new Vector2(30f, 30f)));
            }
            menu.SetAsLastSibling();
        }

        public void Show(Hotspot hotspot)
        {
            current = hotspot;
            title.text = hotspot.displayName;
            lookButton.gameObject.SetActive(hotspot.Has(HotspotVerb.Look));
            useButton.gameObject.SetActive(hotspot.Has(HotspotVerb.Use));
            talkButton.gameObject.SetActive(hotspot.Has(HotspotVerb.Talk));
            menu.gameObject.SetActive(true);
            AudioDirector.Play("ui_tap", 0.5f);
        }

        public void Hide()
        {
            current = null;
            if (menu != null) menu.gameObject.SetActive(false);
        }

        void Choose(HotspotVerb verb)
        {
            var hotspot = current;
            Hide();
            if (hotspot != null) hotspot.Interact(verb);
        }

        void LateUpdate()
        {
            if (cam == null) return;
            bool showMarkers = !GameInput.WorldLocked;

            for (int i = 0; i < markers.Count; i++)
            {
                bool visible = showMarkers && hotspots[i] != current && Place(markers[i], markerPoints[i]);
                markers[i].gameObject.SetActive(visible);
            }

            if (current == null) return;
            if (GameInput.WorldLocked) { Hide(); return; }
            int index = hotspots.IndexOf(current);
            if (index >= 0 && !Place(menu, markerPoints[index])) Hide();
        }

        bool Place(RectTransform element, Vector3 worldPoint)
        {
            var screen = cam.WorldToScreenPoint(worldPoint);
            if (screen.z <= 0f) return false;
            if (!RectTransformUtility.ScreenPointToLocalPointInRectangle(area, screen, null, out var local)) return false;
            element.anchoredPosition = local;
            return true;
        }
    }
}
