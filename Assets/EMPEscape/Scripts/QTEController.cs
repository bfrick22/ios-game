using System;
using System.Collections;
using UnityEngine;
using UnityEngine.UI;

namespace EMPEscape
{
    /// <summary>Runs one quick-time event and reports success or failure.</summary>
    public class QTEController : MonoBehaviour
    {
        RectTransform root;
        RectTransform button;
        QTEPrompt prompt;
        Text label;
        Image ring;
        Image progress;

        public void Build(RectTransform parent)
        {
            root = UIFactory.NewRect("QTE", parent).Stretch();

            var dim = UIFactory.Panel("Dim", root, new Color(0f, 0f, 0f, 0.35f));
            dim.rectTransform.Stretch();
            dim.raycastTarget = false;

            ring = UIFactory.Panel("Ring", root, new Color(1f, 1f, 1f, 0.25f));
            ring.sprite = UIFactory.CircleSprite;
            ring.type = Image.Type.Filled;
            ring.fillMethod = Image.FillMethod.Radial360;
            ring.raycastTarget = false;
            ring.rectTransform.Center(new Vector2(320f, 320f));

            var buttonImage = UIFactory.Panel("Button", root, new Color(0.85f, 0.2f, 0.15f, 0.95f));
            buttonImage.sprite = UIFactory.CircleSprite;
            button = buttonImage.rectTransform.Center(new Vector2(240f, 240f));
            prompt = buttonImage.gameObject.AddComponent<QTEPrompt>();

            label = UIFactory.Label("Label", button, 44, TextAnchor.MiddleCenter, Color.white);
            label.rectTransform.Stretch();
            label.fontStyle = FontStyle.Bold;

            var bar = UIFactory.Panel("ProgressBack", root, new Color(1f, 1f, 1f, 0.2f));
            bar.raycastTarget = false;
            bar.rectTransform.Center(new Vector2(420f, 18f)).anchoredPosition = new Vector2(0f, -210f);
            progress = UIFactory.Panel("Progress", bar.transform, new Color(1f, 0.85f, 0.3f, 1f));
            progress.raycastTarget = false;
            progress.type = Image.Type.Filled;
            progress.sprite = UIFactory.WhiteSprite;
            progress.fillMethod = Image.FillMethod.Horizontal;
            progress.rectTransform.Stretch();

            root.gameObject.SetActive(false);
        }

        public IEnumerator Run(QTESpec spec, Action<bool> onDone)
        {
            prompt.ResetState();
            label.text = spec.type == QTEType.Mash ? "MASH" : spec.type == QTEType.Hold ? "HOLD" : "TAP";
            progress.transform.parent.gameObject.SetActive(spec.type != QTEType.Tap);
            progress.fillAmount = 0f;
            button.anchoredPosition = new Vector2(UnityEngine.Random.Range(-260f, 260f), UnityEngine.Random.Range(-40f, 120f));
            ring.rectTransform.anchoredPosition = button.anchoredPosition;
            root.gameObject.SetActive(true);

            float elapsed = 0f;
            float heldFor = 0f;
            int lastPresses = 0;
            bool success = false;

            while (elapsed < spec.window && !success)
            {
                elapsed += Time.deltaTime;
                ring.fillAmount = 1f - elapsed / spec.window;

                switch (spec.type)
                {
                    case QTEType.Tap:
                        success = prompt.PressCount > 0;
                        break;
                    case QTEType.Mash:
                        progress.fillAmount = prompt.PressCount / Mathf.Max(1f, spec.amount);
                        success = prompt.PressCount >= spec.amount;
                        break;
                    case QTEType.Hold:
                        heldFor = prompt.IsHeld ? heldFor + Time.deltaTime : Mathf.Max(0f, heldFor - Time.deltaTime * 2f);
                        progress.fillAmount = heldFor / Mathf.Max(0.01f, spec.amount);
                        success = heldFor >= spec.amount;
                        break;
                }

                // Pulse on each press so mashing feels physical.
                if (prompt.PressCount != lastPresses)
                {
                    lastPresses = prompt.PressCount;
                    button.localScale = Vector3.one * 0.88f;
                }
                button.localScale = Vector3.Lerp(button.localScale, Vector3.one, 12f * Time.deltaTime);

                yield return null;
            }

            label.text = success ? "GOT IT" : "MISSED";
            yield return new WaitForSeconds(0.35f);
            root.gameObject.SetActive(false);
            onDone(success);
        }
    }
}
