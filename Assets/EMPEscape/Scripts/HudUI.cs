using UnityEngine;
using UnityEngine.UI;

namespace EMPEscape
{
    /// <summary>Bottom-right buttons while exploring: PHONE and LIGHT (once you have the phone) and CHOICES.</summary>
    public class HudUI : MonoBehaviour
    {
        RectTransform root;
        GameObject phoneButton;
        GameObject lightButton;
        Text lightLabel;

        public void Build(RectTransform parent, PhoneUI phone, DecisionsUI decisions)
        {
            root = UIFactory.NewRect("Hud", parent).Anchor(new Vector2(1f, 0f), new Vector2(1f, 0f), new Vector2(-250f, 30f), new Vector2(-24f, 270f));
            var layout = root.gameObject.AddComponent<VerticalLayoutGroup>();
            layout.spacing = 12f;
            layout.childAlignment = TextAnchor.LowerCenter;
            layout.childControlWidth = layout.childControlHeight = true;
            layout.childForceExpandWidth = true;
            layout.childForceExpandHeight = false;

            phoneButton = AddButton("PHONE", phone.Open, out _);
            lightButton = AddButton("LIGHT", phone.ToggleFlashlight, out lightLabel);
            AddButton("CHOICES", decisions.Open, out _);
        }

        GameObject AddButton(string name, UnityEngine.Events.UnityAction action, out Text label)
        {
            var button = UIFactory.MakeButton(name, root, 30, out label);
            label.text = name;
            button.gameObject.AddComponent<LayoutElement>().preferredHeight = 70f;
            button.onClick.AddListener(action);
            return button.gameObject;
        }

        void Update()
        {
            bool visible = !GameInput.WorldLocked;
            if (root.gameObject.activeSelf != visible) root.gameObject.SetActive(visible);
            if (!visible) return;

            bool hasPhone = StoryDirector.Instance != null && StoryDirector.Instance.GetFlag(PhoneUI.OwnedFlag);
            if (phoneButton.activeSelf != hasPhone) phoneButton.SetActive(hasPhone);
            if (lightButton.activeSelf != hasPhone) lightButton.SetActive(hasPhone);
            lightLabel.text = Flashlight.Player != null && Flashlight.Player.IsOn ? "LIGHT: ON" : "LIGHT";
        }
    }
}
