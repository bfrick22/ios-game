using UnityEngine;
using UnityEngine.UI;

namespace EMPEscape
{
    /// <summary>Builds UI from code so the slice needs no prefabs or hand-built canvases.</summary>
    public static class UIFactory
    {
        static Font font;
        static Sprite circle;
        static Sprite white;

        public static Font Font => font != null ? font : (font = Resources.GetBuiltinResource<Font>("LegacyRuntime.ttf"));

        public static Sprite CircleSprite
        {
            get
            {
                if (circle != null) return circle;
                const int size = 128;
                var texture = new Texture2D(size, size, TextureFormat.RGBA32, false);
                var center = (size - 1) / 2f;
                for (int y = 0; y < size; y++)
                for (int x = 0; x < size; x++)
                {
                    var distance = Vector2.Distance(new Vector2(x, y), new Vector2(center, center));
                    var alpha = Mathf.Clamp01(center - distance);
                    texture.SetPixel(x, y, new Color(1f, 1f, 1f, alpha));
                }
                texture.Apply();
                circle = Sprite.Create(texture, new Rect(0, 0, size, size), new Vector2(0.5f, 0.5f));
                return circle;
            }
        }

        public static Sprite WhiteSprite
        {
            get
            {
                if (white != null) return white;
                var texture = Texture2D.whiteTexture;
                white = Sprite.Create(texture, new Rect(0, 0, texture.width, texture.height), new Vector2(0.5f, 0.5f));
                return white;
            }
        }

        static Sprite ring;
        static Sprite arrow;

        /// <summary>Hollow circle: reticles and target markers.</summary>
        public static Sprite RingSprite
        {
            get
            {
                if (ring == null)
                    ring = Procedural(128, (x, y, c) => Mathf.Clamp01(4f - Mathf.Abs(Vector2.Distance(new Vector2(x, y), new Vector2(c, c)) - (c - 6f))));
                return ring;
            }
        }

        /// <summary>Arrow pointing right. Rotate the Image to point it elsewhere.</summary>
        public static Sprite ArrowSprite
        {
            get
            {
                if (arrow == null)
                    arrow = Procedural(128, (x, y, c) =>
                    {
                        float dy = Mathf.Abs(y - c);
                        if (x >= 10f && x <= 72f && dy <= 13f) return 1f;                 // shaft
                        if (x >= 64f && x <= 120f && dy <= (120f - x) * 0.85f) return 1f; // head
                        return 0f;
                    });
                return arrow;
            }
        }

        static Sprite Procedural(int size, System.Func<float, float, float, float> alpha)
        {
            var texture = new Texture2D(size, size, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp };
            float center = (size - 1) / 2f;
            for (int y = 0; y < size; y++)
            for (int x = 0; x < size; x++)
                texture.SetPixel(x, y, new Color(1f, 1f, 1f, alpha(x, y, center)));
            texture.Apply();
            return Sprite.Create(texture, new Rect(0, 0, size, size), new Vector2(0.5f, 0.5f));
        }

        public static Canvas CreateCanvas(string name, Transform parent)
        {
            var go = new GameObject(name, typeof(RectTransform), typeof(Canvas), typeof(CanvasScaler), typeof(GraphicRaycaster));
            go.transform.SetParent(parent, false);
            var canvas = go.GetComponent<Canvas>();
            canvas.renderMode = RenderMode.ScreenSpaceOverlay;
            canvas.sortingOrder = 10;
            var scaler = go.GetComponent<CanvasScaler>();
            scaler.uiScaleMode = CanvasScaler.ScaleMode.ScaleWithScreenSize;
            scaler.referenceResolution = new Vector2(1920f, 1080f);
            scaler.matchWidthOrHeight = 0.5f;
            return canvas;
        }

        public static RectTransform NewRect(string name, Transform parent)
        {
            var go = new GameObject(name, typeof(RectTransform));
            go.transform.SetParent(parent, false);
            return (RectTransform)go.transform;
        }

        public static Image Panel(string name, Transform parent, Color color)
        {
            var image = NewRect(name, parent).gameObject.AddComponent<Image>();
            image.color = color;
            return image;
        }

        public static Text Label(string name, Transform parent, int size, TextAnchor alignment, Color color)
        {
            var text = NewRect(name, parent).gameObject.AddComponent<Text>();
            text.font = Font;
            text.fontSize = size;
            text.alignment = alignment;
            text.color = color;
            text.horizontalOverflow = HorizontalWrapMode.Wrap;
            text.verticalOverflow = VerticalWrapMode.Overflow;
            text.raycastTarget = false;
            return text;
        }

        public static Button MakeButton(string name, Transform parent, int fontSize, out Text label)
        {
            var background = Panel(name, parent, new Color(0.05f, 0.05f, 0.07f, 0.85f));
            var button = background.gameObject.AddComponent<Button>();
            var colors = button.colors;
            colors.highlightedColor = new Color(1f, 0.85f, 0.6f);
            colors.pressedColor = new Color(1f, 0.7f, 0.35f);
            button.colors = colors;
            label = Label("Label", background.transform, fontSize, TextAnchor.MiddleCenter, Color.white);
            label.rectTransform.Stretch(new Vector2(24f, 8f));
            button.onClick.AddListener(() => AudioDirector.Play("ui_tap", 0.6f));
            return button;
        }

        /// <summary>
        /// A vertical scrolling list. Children added to <paramref name="content"/> stack top to bottom and size
        /// themselves (Text wraps to the list's width).
        /// </summary>
        public static ScrollRect ScrollList(string name, Transform parent, float spacing, out RectTransform content)
        {
            var root = NewRect(name, parent);
            var scroll = root.gameObject.AddComponent<ScrollRect>();
            scroll.horizontal = false;
            scroll.movementType = ScrollRect.MovementType.Clamped;
            scroll.scrollSensitivity = 40f;

            var viewport = NewRect("Viewport", root).Stretch();
            viewport.gameObject.AddComponent<RectMask2D>();
            var catcher = viewport.gameObject.AddComponent<Image>(); // lets drags anywhere in the list scroll it
            catcher.color = new Color(0f, 0f, 0f, 0f);

            content = NewRect("Content", viewport);
            content.anchorMin = new Vector2(0f, 1f);
            content.anchorMax = new Vector2(1f, 1f);
            content.pivot = new Vector2(0.5f, 1f);
            content.sizeDelta = Vector2.zero;
            content.anchoredPosition = Vector2.zero;
            var layout = content.gameObject.AddComponent<VerticalLayoutGroup>();
            layout.spacing = spacing;
            layout.padding = new RectOffset(8, 8, 8, 8);
            layout.childControlWidth = true;
            layout.childControlHeight = true;
            layout.childForceExpandWidth = true;
            layout.childForceExpandHeight = false;
            content.gameObject.AddComponent<ContentSizeFitter>().verticalFit = ContentSizeFitter.FitMode.PreferredSize;

            scroll.viewport = viewport;
            scroll.content = content;
            return scroll;
        }

        /// <summary>A wrapping text block for lists (rich text on: color, b, i, size tags).</summary>
        public static Text Paragraph(string name, Transform parent, int size, Color color, string text)
        {
            var label = Label(name, parent, size, TextAnchor.UpperLeft, color);
            label.supportRichText = true;
            label.text = text;
            return label;
        }

        /// <summary>A button sized by its list (layout height), left-aligned label.</summary>
        public static Button ListButton(string name, Transform parent, int fontSize, float height, out Text label)
        {
            var button = MakeButton(name, parent, fontSize, out label);
            label.alignment = TextAnchor.MiddleLeft;
            label.supportRichText = true;
            button.gameObject.AddComponent<LayoutElement>().preferredHeight = height;
            return button;
        }

        // ---- RectTransform helpers ----

        public static RectTransform Stretch(this RectTransform rt) => rt.Stretch(Vector2.zero);

        public static RectTransform Stretch(this RectTransform rt, Vector2 padding)
        {
            rt.anchorMin = Vector2.zero;
            rt.anchorMax = Vector2.one;
            rt.offsetMin = padding;
            rt.offsetMax = -padding;
            return rt;
        }

        public static RectTransform Center(this RectTransform rt, Vector2 size)
        {
            rt.anchorMin = rt.anchorMax = rt.pivot = new Vector2(0.5f, 0.5f);
            rt.sizeDelta = size;
            rt.anchoredPosition = Vector2.zero;
            return rt;
        }

        public static RectTransform Anchor(this RectTransform rt, Vector2 min, Vector2 max, Vector2 offsetMin, Vector2 offsetMax)
        {
            rt.anchorMin = min;
            rt.anchorMax = max;
            rt.offsetMin = offsetMin;
            rt.offsetMax = offsetMax;
            return rt;
        }
    }
}
