using UnityEngine;

namespace EMPEscape
{
    /// <summary>The floating stick drawn where the thumb lands. PlayerController drives it.</summary>
    public class JoystickUI : MonoBehaviour
    {
        // Diameter in canvas units at the 1080p reference height: 2 x PlayerController.stickRadius (0.1) x 1080.
        const float RingSize = 216f;

        RectTransform area;
        RectTransform ring;
        RectTransform knob;

        public void Build(RectTransform parent)
        {
            area = UIFactory.NewRect("Joystick", parent).Stretch();

            var ringImage = UIFactory.Panel("Ring", area, new Color(1f, 1f, 1f, 0.16f));
            ringImage.sprite = UIFactory.CircleSprite;
            ringImage.raycastTarget = false;
            ring = ringImage.rectTransform.Center(new Vector2(RingSize, RingSize));

            var knobImage = UIFactory.Panel("Knob", ring, new Color(1f, 1f, 1f, 0.5f));
            knobImage.sprite = UIFactory.CircleSprite;
            knobImage.raycastTarget = false;
            knob = knobImage.rectTransform.Center(new Vector2(92f, 92f));

            area.gameObject.SetActive(false);
        }

        public void Show(Vector2 screenPos)
        {
            area.gameObject.SetActive(true);
            MoveBase(screenPos);
            knob.anchoredPosition = Vector2.zero;
        }

        public void MoveBase(Vector2 screenPos)
        {
            if (RectTransformUtility.ScreenPointToLocalPointInRectangle(area, screenPos, null, out var local))
                ring.anchoredPosition = local;
        }

        public void SetKnob(Vector2 stick) => knob.anchoredPosition = stick * (RingSize * 0.5f);

        public void Hide() => area.gameObject.SetActive(false);
    }
}
