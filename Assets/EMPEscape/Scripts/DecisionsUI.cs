using UnityEngine;
using UnityEngine.UI;

namespace EMPEscape
{
    /// <summary>The CHOICES screen: every decision the player has made, newest first, kept across sessions.</summary>
    public class DecisionsUI : MonoBehaviour
    {
        RectTransform root;
        RectTransform list;
        ScrollRect scroll;
        Text empty;

        public bool IsOpen => root != null && root.gameObject.activeSelf;

        public void Build(RectTransform parent)
        {
            var shade = UIFactory.Panel("Choices", parent, new Color(0f, 0f, 0f, 0.75f));
            root = shade.rectTransform.Stretch();

            var panel = UIFactory.Panel("Panel", root, new Color(0.09f, 0.09f, 0.1f, 0.97f));
            var box = panel.rectTransform.Center(new Vector2(1150f, 820f));

            var title = UIFactory.Label("Title", box, 44, TextAnchor.MiddleLeft, new Color(1f, 0.8f, 0.4f));
            title.fontStyle = FontStyle.Bold;
            title.text = "YOUR CHOICES";
            title.rectTransform.Anchor(new Vector2(0f, 1f), new Vector2(1f, 1f), new Vector2(40f, -90f), new Vector2(-40f, -20f));

            scroll = UIFactory.ScrollList("List", box, 14f, out list);
            ((RectTransform)scroll.transform).Anchor(Vector2.zero, Vector2.one, new Vector2(32f, 110f), new Vector2(-32f, -100f));

            empty = UIFactory.Label("Empty", box, 32, TextAnchor.MiddleCenter, new Color(1f, 1f, 1f, 0.5f));
            empty.text = "No choices yet. Talk to people. What you decide is remembered.";
            empty.rectTransform.Center(new Vector2(900f, 120f));

            var clear = UIFactory.MakeButton("Clear", box, 32, out var clearLabel);
            clearLabel.text = "Clear all";
            clear.GetComponent<RectTransform>().Anchor(Vector2.zero, Vector2.zero, new Vector2(40f, 24f), new Vector2(280f, 90f));
            clear.onClick.AddListener(() =>
            {
                DecisionLog.Clear();
                Refresh();
            });

            var close = UIFactory.MakeButton("Close", box, 32, out var closeLabel);
            closeLabel.text = "Close";
            close.GetComponent<RectTransform>().Anchor(new Vector2(1f, 0f), new Vector2(1f, 0f), new Vector2(-280f, 24f), new Vector2(-40f, 90f));
            close.onClick.AddListener(Close);

            root.gameObject.SetActive(false);
        }

        public void Open()
        {
            if (IsOpen) return;
            GameInput.Lock();
            root.gameObject.SetActive(true);
            Refresh();
        }

        public void Close()
        {
            if (!IsOpen) return;
            root.gameObject.SetActive(false);
            GameInput.Unlock();
        }

        void Refresh()
        {
            for (int i = list.childCount - 1; i >= 0; i--) Destroy(list.GetChild(i).gameObject);
            var all = DecisionLog.All;
            empty.enabled = all.Count == 0;
            for (int i = all.Count - 1; i >= 0; i--)
            {
                var d = all[i];
                UIFactory.Paragraph("Decision", list, 32, Color.white,
                    $"{d.text}\n<size=24><color=#8a8a8a>{d.scene}  ·  {d.time}</color></size>");
            }
            scroll.verticalNormalizedPosition = 1f;
        }
    }
}
