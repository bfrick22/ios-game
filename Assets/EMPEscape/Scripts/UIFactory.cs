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
