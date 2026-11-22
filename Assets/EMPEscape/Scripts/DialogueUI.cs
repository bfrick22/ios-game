using System;
using System.Collections;
using System.Collections.Generic;
using Ink.Runtime;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

namespace EMPEscape
{
    /// <summary>Subtitles, timed dialogue choices, "will remember that" toasts, and the end screen.</summary>
    public class DialogueUI : MonoBehaviour, IStoryPresenter
    {
        const int MaxChoices = 4;

        public float charactersPerSecond = 55f;

        RectTransform subtitle;
        Text speakerLabel;
        Text lineLabel;
        Text continueHint;

        RectTransform choicePanel;
        readonly Button[] choiceButtons = new Button[MaxChoices];
        readonly Text[] choiceLabels = new Text[MaxChoices];
        RectTransform timerBar;
        Image timerFill;
        int pickedChoice = -1;

        CanvasGroup rememberGroup;
        Text rememberLabel;
        Coroutine rememberRoutine;

        RectTransform endScreen;
        Text endTitle;

        RectTransform deathScreen;
        Text deathTitle;
        Action onRetry;

        public void Build(RectTransform parent)
        {
            // Subtitle box along the bottom.
            var subtitleBox = UIFactory.Panel("Subtitle", parent, new Color(0f, 0f, 0f, 0.65f));
            subtitle = subtitleBox.rectTransform.Anchor(new Vector2(0.12f, 0f), new Vector2(0.88f, 0f), new Vector2(0f, 30f), new Vector2(0f, 230f));
            subtitleBox.raycastTarget = false;

            speakerLabel = UIFactory.Label("Speaker", subtitle, 34, TextAnchor.UpperLeft, new Color(1f, 0.8f, 0.4f));
            speakerLabel.fontStyle = FontStyle.Bold;
            speakerLabel.rectTransform.Anchor(new Vector2(0f, 1f), new Vector2(1f, 1f), new Vector2(36f, -62f), new Vector2(-36f, -16f));

            lineLabel = UIFactory.Label("Line", subtitle, 38, TextAnchor.UpperLeft, Color.white);
            lineLabel.rectTransform.Stretch().Anchor(Vector2.zero, Vector2.one, new Vector2(36f, 20f), new Vector2(-36f, -66f));

            continueHint = UIFactory.Label("Continue", subtitle, 26, TextAnchor.LowerRight, new Color(1f, 1f, 1f, 0.6f));
            continueHint.text = "TAP TO CONTINUE";
            continueHint.rectTransform.Stretch(new Vector2(28f, 14f));

            // Choices stacked above the subtitle.
            choicePanel = UIFactory.NewRect("Choices", parent).Anchor(new Vector2(0.25f, 0f), new Vector2(0.75f, 0f), new Vector2(0f, 250f), new Vector2(0f, 250f + MaxChoices * 96f + 30f));
            var layout = choicePanel.gameObject.AddComponent<VerticalLayoutGroup>();
            layout.spacing = 12f;
            layout.childAlignment = TextAnchor.LowerCenter;
            layout.childControlWidth = true;
            layout.childControlHeight = true;
            layout.childForceExpandWidth = true;
            layout.childForceExpandHeight = false;

            for (int i = 0; i < MaxChoices; i++)
            {
                var button = UIFactory.MakeButton($"Choice{i}", choicePanel, 34, out var label);
                button.gameObject.AddComponent<LayoutElement>().preferredHeight = 84f;
                int index = i;
                button.onClick.AddListener(() => pickedChoice = index);
                choiceButtons[i] = button;
                choiceLabels[i] = label;
            }

            var timerBack = UIFactory.Panel("Timer", choicePanel, new Color(1f, 1f, 1f, 0.2f));
            timerBack.gameObject.AddComponent<LayoutElement>().preferredHeight = 10f;
            timerBack.raycastTarget = false;
            timerBar = timerBack.rectTransform;
            timerFill = UIFactory.Panel("Fill", timerBar, new Color(1f, 0.8f, 0.4f, 1f));
            timerFill.sprite = UIFactory.WhiteSprite;
            timerFill.type = Image.Type.Filled;
            timerFill.fillMethod = Image.FillMethod.Horizontal;
            timerFill.fillOrigin = (int)Image.OriginHorizontal.Left;
            timerFill.raycastTarget = false;
            timerFill.rectTransform.Stretch();

            // "Ray will remember that." toast, top-left like Telltale.
            var toast = UIFactory.Panel("Remember", parent, new Color(0f, 0f, 0f, 0.6f));
            toast.raycastTarget = false;
            toast.rectTransform.Anchor(new Vector2(0f, 1f), new Vector2(0f, 1f), new Vector2(30f, -110f), new Vector2(720f, -30f));
            rememberGroup = toast.gameObject.AddComponent<CanvasGroup>();
            rememberGroup.alpha = 0f;
            rememberGroup.blocksRaycasts = false;
            rememberLabel = UIFactory.Label("Text", toast.transform, 32, TextAnchor.MiddleLeft, Color.white);
            rememberLabel.fontStyle = FontStyle.Italic;
            rememberLabel.rectTransform.Stretch(new Vector2(24f, 6f));

            // End screen.
            var end = UIFactory.Panel("EndScreen", parent, new Color(0f, 0f, 0f, 0.85f));
            endScreen = end.rectTransform.Stretch();
            endTitle = UIFactory.Label("Title", endScreen, 64, TextAnchor.MiddleCenter, Color.white);
            endTitle.rectTransform.Center(new Vector2(1400f, 160f)).anchoredPosition = new Vector2(0f, 80f);
            var restart = UIFactory.MakeButton("Restart", endScreen, 38, out var restartLabel);
            restartLabel.text = "Restart";
            restart.GetComponent<RectTransform>().Center(new Vector2(360f, 96f)).anchoredPosition = new Vector2(0f, -90f);
            restart.onClick.AddListener(() => SceneManager.LoadScene(SceneManager.GetActiveScene().buildIndex));

            // Death screen. Retry replays the knot from where it started.
            var death = UIFactory.Panel("DeathScreen", parent, new Color(0.25f, 0f, 0f, 0.88f));
            deathScreen = death.rectTransform.Stretch();
            deathTitle = UIFactory.Label("Title", deathScreen, 64, TextAnchor.MiddleCenter, Color.white);
            deathTitle.rectTransform.Center(new Vector2(1400f, 160f)).anchoredPosition = new Vector2(0f, 80f);
            var retry = UIFactory.MakeButton("Retry", deathScreen, 38, out var retryLabel);
            retryLabel.text = "Retry";
            retry.GetComponent<RectTransform>().Center(new Vector2(360f, 96f)).anchoredPosition = new Vector2(0f, -90f);
            retry.onClick.AddListener(() =>
            {
                deathScreen.gameObject.SetActive(false);
                var action = onRetry;
                onRetry = null;
                action?.Invoke();
            });
            deathScreen.gameObject.SetActive(false);

            subtitle.gameObject.SetActive(false);
            choicePanel.gameObject.SetActive(false);
            endScreen.gameObject.SetActive(false);
        }

        public IEnumerator ShowLine(string speaker, string line)
        {
            subtitle.gameObject.SetActive(true);
            speakerLabel.text = speaker ?? "";
            continueHint.enabled = false;
            lineLabel.text = "";

            yield return null; // never let the tap that started this also skip it

            float shown = 0f;
            int lastCount = -1;
            while (lastCount < line.Length)
            {
                shown = GameInput.PressedThisFrame(out _) ? line.Length : shown + charactersPerSecond * Time.deltaTime;
                int count = Mathf.Min(line.Length, (int)shown);
                if (count != lastCount)
                {
                    lineLabel.text = line.Substring(0, count);
                    lastCount = count;
                }
                if (count >= line.Length) break;
                yield return null;
            }

            yield return null;
            continueHint.enabled = true;
            while (!GameInput.PressedThisFrame(out _)) yield return null;
        }

        public IEnumerator ShowChoices(List<Choice> choices, float timerSeconds, Action<int> onPicked)
        {
            if (choices.Count > MaxChoices)
                Debug.LogWarning($"[DialogueUI] {choices.Count} choices offered; only the first {MaxChoices} are shown.");

            continueHint.enabled = false;
            for (int i = 0; i < MaxChoices; i++)
            {
                bool active = i < choices.Count;
                choiceButtons[i].gameObject.SetActive(active);
                if (active) choiceLabels[i].text = choices[i].text.Trim();
            }

            bool timed = timerSeconds > 0f;
            timerBar.gameObject.SetActive(timed);
            timerFill.fillAmount = 1f;
            choicePanel.gameObject.SetActive(true);

            pickedChoice = -1;
            float elapsed = 0f;
            int visible = Mathf.Min(choices.Count, MaxChoices);
            while (pickedChoice < 0)
            {
                if (timed)
                {
                    elapsed += Time.deltaTime;
                    timerFill.fillAmount = 1f - elapsed / timerSeconds;
                    if (elapsed >= timerSeconds) pickedChoice = visible - 1; // last choice = silence
                }
                yield return null;
            }

            choicePanel.gameObject.SetActive(false);
            onPicked(pickedChoice);
        }

        public void HideLine() => subtitle.gameObject.SetActive(false);

        public void ShowRemember(string text)
        {
            if (rememberRoutine != null) StopCoroutine(rememberRoutine);
            rememberRoutine = StartCoroutine(Remember(text));
            AudioDirector.Play("remember_chime", 0.7f);
        }

        IEnumerator Remember(string text)
        {
            rememberLabel.text = text;
            for (float t = 0f; t < 0.3f; t += Time.deltaTime) { rememberGroup.alpha = t / 0.3f; yield return null; }
            rememberGroup.alpha = 1f;
            yield return new WaitForSeconds(2.5f);
            for (float t = 0f; t < 0.6f; t += Time.deltaTime) { rememberGroup.alpha = 1f - t / 0.6f; yield return null; }
            rememberGroup.alpha = 0f;
        }

        public void ShowDeath(string message, Action retry)
        {
            deathTitle.text = message;
            onRetry = retry;
            deathScreen.gameObject.SetActive(true);
            AudioDirector.Play("death_sting");
        }

        public void ShowEndScreen(string title)
        {
            endTitle.text = title;
            endScreen.gameObject.SetActive(true);
        }
    }
}
