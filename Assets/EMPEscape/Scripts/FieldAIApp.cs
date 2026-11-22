using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace EMPEscape
{
    /// <summary>
    /// Field-AI: presented as a small language model running offline on the phone. It's scripted: the player
    /// taps a preset question from the field guide and the written answer types out like a model replying.
    /// Questions from packs that aren't loaded show as NOT LOADED and get a "find the data" reply.
    /// </summary>
    public class FieldAIApp : PhoneApp
    {
        const int CostPerAnswer = 4;
        const float CharactersPerSecond = 75f;
        const string AiName = "<color=#a8e6a1><b>FIELD-AI</b></color>\n";

        public override string Title => "Field-AI";

        ScrollRect chatScroll;
        RectTransform chat;
        RectTransform questions;
        readonly HashSet<string> asked = new HashSet<string>();
        bool answering;
        bool greeted;

        protected override void Create()
        {
            chatScroll = UIFactory.ScrollList("Chat", Page, 16f, out chat);
            ((RectTransform)chatScroll.transform).Anchor(new Vector2(0f, 0.45f), Vector2.one, Vector2.zero, Vector2.zero);

            var divider = UIFactory.Panel("Divider", Page, new Color(1f, 1f, 1f, 0.12f));
            divider.raycastTarget = false;
            divider.rectTransform.Anchor(new Vector2(0f, 0.45f), new Vector2(1f, 0.45f), new Vector2(0f, -1f), new Vector2(0f, 1f));

            var questionScroll = UIFactory.ScrollList("Questions", Page, 8f, out questions);
            ((RectTransform)questionScroll.transform).Anchor(Vector2.zero, new Vector2(1f, 0.45f), Vector2.zero, new Vector2(0f, -6f));
        }

        public override void Show()
        {
            base.Show();
            if (!greeted)
            {
                greeted = true;
                AddMessage(AiName + "Online. Offline survival model, no signal needed.\nPick a question below.", false);
            }
            RebuildQuestions();
            ScrollToEnd();
        }

        void RebuildQuestions()
        {
            for (int i = questions.childCount - 1; i >= 0; i--) Object.Destroy(questions.GetChild(i).gameObject);
            UIFactory.Paragraph("Header", questions, 22, PhoneUI.DimColor, "ASK FIELD-AI");

            var guide = Phone.Guide;
            foreach (bool loadedPass in new[] { true, false })
            {
                foreach (var entry in guide.Entries)
                {
                    if (string.IsNullOrEmpty(entry.question) || guide.IsLoaded(entry) != loadedPass) continue;
                    var button = UIFactory.ListButton("Question", questions, 26, loadedPass ? 74f : 96f, out var label);
                    if (!loadedPass)
                        label.text = $"<color=#6e7681>{entry.question}\n<size=20>NOT LOADED: {guide.FindPack(entry.pack).name}</size></color>";
                    else if (asked.Contains(entry.id))
                        label.text = $"<color=#8b949e>{entry.question}</color>";
                    else
                        label.text = entry.question;
                    button.interactable = !answering;
                    var chosen = entry;
                    button.onClick.AddListener(() => Phone.StartCoroutine(Answer(chosen)));
                }
            }
        }

        IEnumerator Answer(FieldGuide.Entry entry)
        {
            if (answering) yield break;
            answering = true;
            Phone.NavigationLocked = true;
            RebuildQuestions();

            AddMessage($"<color=#f2c46d><b>YOU</b></color>\n{entry.question}", true);
            AudioDirector.Play("msg_out", 0.5f);
            var reply = AddMessage(AiName, false);

            string text;
            bool ok = false;
            if (!Phone.Guide.IsLoaded(entry))
            {
                var pack = Phone.Guide.FindPack(entry.pack);
                text = $"I have a reference to that, but it's in my {pack.name} data, which isn't loaded. {pack.howToGet}";
            }
            else if (!Phone.UseBattery(CostPerAnswer))
            {
                text = "Battery too low to run the model. Charge me with the solar panel.";
            }
            else
            {
                text = entry.answer;
                ok = true;
                asked.Add(entry.id);
            }

            // "Thinking", then the reply types out like a model generating it.
            for (int i = 0; i < 6; i++)
            {
                reply.text = AiName + new string('.', i % 3 + 1);
                yield return new WaitForSeconds(0.16f);
            }
            float shown = 0f;
            int last = 0;
            while (last < text.Length)
            {
                shown += CharactersPerSecond * Time.deltaTime;
                int count = Mathf.Min(text.Length, (int)shown);
                if (count != last)
                {
                    if (count / 4 != last / 4) AudioDirector.Play("ui_type", 0.4f, 0.1f);
                    last = count;
                    reply.text = AiName + text.Substring(0, count);
                    ScrollToEnd();
                }
                yield return null;
            }
            AudioDirector.Play(ok ? "device_beep" : "device_error", 0.6f);

            answering = false;
            Phone.NavigationLocked = false;
            RebuildQuestions();
        }

        Text AddMessage(string text, bool fromPlayer)
        {
            var message = UIFactory.Paragraph("Message", chat, 27, PhoneUI.TextColor, text);
            message.alignment = fromPlayer ? TextAnchor.UpperRight : TextAnchor.UpperLeft;
            while (chat.childCount > 40) Object.DestroyImmediate(chat.GetChild(0).gameObject);
            ScrollToEnd();
            return message;
        }

        void ScrollToEnd()
        {
            Canvas.ForceUpdateCanvases();
            chatScroll.verticalNormalizedPosition = 0f;
        }
    }
}
