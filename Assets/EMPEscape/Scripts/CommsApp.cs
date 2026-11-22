using System;
using System.Collections;
using System.Collections.Generic;
using Ink.Runtime;
using UnityEngine;
using UnityEngine.UI;
using Object = UnityEngine.Object;

namespace EMPEscape
{
    /// <summary>
    /// Comms: local Wi-Fi messaging. There's no internet, but networks with their own power show up as contacts
    /// once the story finds them. Contacts are listed in Resources/Phone/contacts.json; each is visible while its
    /// Ink flag is true and opens an Ink knot shown as a chat: "Name: text" lines arrive as messages, "You: text"
    /// lines are yours, plain lines are system notes, and choices become reply buttons.
    /// </summary>
    public class CommsApp : PhoneApp, IStoryPresenter
    {
        [Serializable]
        class Contact
        {
            public string id;
            public string name;
            public string network;
            public string flag;
            public string knot;
            public string preview;
        }

        [Serializable]
        class FileData
        {
            public Contact[] contacts = new Contact[0];
        }

        struct Message
        {
            public string text;
            public TextAnchor alignment;
        }

        const string ResourcePath = "Phone/contacts";
        static FileData data;

        public override string Title => "Comms";

        ScrollRect listScroll;
        RectTransform list;
        RectTransform threadPage;
        ScrollRect threadScroll;
        RectTransform thread;
        RectTransform replies;
        readonly Dictionary<string, List<Message>> history = new Dictionary<string, List<Message>>();
        Contact open;
        bool busy;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        static void ResetStatics() => data = null;

        static FileData Data
        {
            get
            {
                if (data != null) return data;
                var asset = Resources.Load<TextAsset>(ResourcePath);
                data = asset != null ? JsonUtility.FromJson<FileData>(asset.text) : null;
                if (data == null) data = new FileData();
                return data;
            }
        }

        static bool Visible(Contact contact) =>
            string.IsNullOrEmpty(contact.flag) || (StoryDirector.Instance != null && StoryDirector.Instance.GetFlag(contact.flag));

        /// <summary>The network name of the first contact in range, or null (status bar shows NO SERVICE).</summary>
        public static string ConnectedNetwork()
        {
            foreach (var contact in Data.contacts)
                if (Visible(contact)) return contact.network;
            return null;
        }

        protected override void Create()
        {
            listScroll = UIFactory.ScrollList("Contacts", Page, 10f, out list);
            ((RectTransform)listScroll.transform).Stretch();

            threadPage = UIFactory.NewRect("Thread", Page).Stretch();
            threadScroll = UIFactory.ScrollList("Messages", threadPage, 16f, out thread);
            ((RectTransform)threadScroll.transform).Anchor(new Vector2(0f, 0.34f), Vector2.one, Vector2.zero, Vector2.zero);
            replies = UIFactory.NewRect("Replies", threadPage).Anchor(Vector2.zero, new Vector2(1f, 0.34f), new Vector2(0f, 0f), new Vector2(0f, -8f));
            var layout = replies.gameObject.AddComponent<VerticalLayoutGroup>();
            layout.spacing = 8f;
            layout.childAlignment = TextAnchor.LowerCenter;
            layout.childControlWidth = layout.childControlHeight = true;
            layout.childForceExpandWidth = true;
            layout.childForceExpandHeight = false;
        }

        public override void Show()
        {
            base.Show();
            if (open != null && busy) return;
            ShowList();
        }

        public override bool Back()
        {
            if (busy) return true;
            if (!threadPage.gameObject.activeSelf) return false;
            ShowList();
            return true;
        }

        void ShowList()
        {
            open = null;
            threadPage.gameObject.SetActive(false);
            listScroll.gameObject.SetActive(true);
            for (int i = list.childCount - 1; i >= 0; i--) Object.Destroy(list.GetChild(i).gameObject);

            bool any = false;
            foreach (var contact in Data.contacts)
            {
                if (!Visible(contact)) continue;
                any = true;
                var button = UIFactory.ListButton("Contact", list, 28, 104f, out var label);
                label.text = $"<b>{contact.name}</b>\n<size=21><color=#8b949e>{contact.network}  ·  {contact.preview}</color></size>";
                var chosen = contact;
                button.onClick.AddListener(() => OpenThread(chosen));
            }
            if (!any)
                UIFactory.Paragraph("Searching", list, 26, PhoneUI.DimColor,
                    "Searching for Wi-Fi...\n\nNo networks in range. The cell towers are down, but a network with its own power could still be out there.");
        }

        void OpenThread(Contact contact)
        {
            open = contact;
            listScroll.gameObject.SetActive(false);
            threadPage.gameObject.SetActive(true);
            for (int i = thread.childCount - 1; i >= 0; i--) Object.Destroy(thread.GetChild(i).gameObject);
            ClearReplies();
            foreach (var message in History(contact)) Render(message);
            ScrollToEnd();

            var story = StoryDirector.Instance;
            if (story != null && !story.IsRunning && !string.IsNullOrEmpty(contact.knot)) story.RunKnot(contact.knot, this);
        }

        // ---------- IStoryPresenter: the knot's lines and choices as a chat ----------

        public IEnumerator ShowLine(string speaker, string line)
        {
            SetBusy(true);
            if (speaker == "You")
            {
                Add($"<color=#f2c46d><b>You</b></color>\n{line}", TextAnchor.UpperRight);
                AudioDirector.Play("msg_out", 0.5f);
            }
            else if (speaker == null)
            {
                Add($"<i><color=#8b949e>{line}</color></i>", TextAnchor.UpperCenter);
            }
            else
            {
                var typing = UIFactory.Paragraph("Typing", thread, 26, PhoneUI.DimColor, speaker + " is typing...");
                ScrollToEnd();
                yield return new WaitForSeconds(Mathf.Clamp(line.Length * 0.02f, 0.5f, 1.4f));
                Object.Destroy(typing.gameObject);
                Add($"<color=#63d2c6><b>{speaker}</b></color>\n{line}", TextAnchor.UpperLeft);
                AudioDirector.Play("msg_in", 0.6f);
            }
            yield return new WaitForSeconds(0.35f);
        }

        public IEnumerator ShowChoices(List<Choice> choices, float timerSeconds, Action<int> onPicked)
        {
            SetBusy(true);
            ClearReplies();
            int picked = -1;
            for (int i = 0; i < choices.Count; i++)
            {
                var button = UIFactory.ListButton("Reply", replies, 26, 70f, out var label);
                label.text = choices[i].text.Trim();
                button.GetComponent<Image>().color = new Color(0.12f, 0.24f, 0.26f, 0.95f);
                int index = i;
                button.onClick.AddListener(() => picked = index);
            }
            while (picked < 0) yield return null;

            ClearReplies();
            Add($"<color=#f2c46d><b>You</b></color>\n{choices[picked].text.Trim()}", TextAnchor.UpperRight);
            AudioDirector.Play("msg_out", 0.5f);
            onPicked(picked);
        }

        public void HideLine() => SetBusy(false); // the knot has finished

        // ---------- helpers ----------

        void SetBusy(bool value)
        {
            busy = value;
            Phone.NavigationLocked = value;
        }

        List<Message> History(Contact contact)
        {
            if (!history.TryGetValue(contact.id, out var messages)) history[contact.id] = messages = new List<Message>();
            return messages;
        }

        void Add(string text, TextAnchor alignment)
        {
            var message = new Message { text = text, alignment = alignment };
            if (open != null) History(open).Add(message);
            Render(message);
            ScrollToEnd();
        }

        void Render(Message message)
        {
            var label = UIFactory.Paragraph("Message", thread, 27, PhoneUI.TextColor, message.text);
            label.alignment = message.alignment;
        }

        void ClearReplies()
        {
            for (int i = replies.childCount - 1; i >= 0; i--) Object.Destroy(replies.GetChild(i).gameObject);
        }

        void ScrollToEnd()
        {
            Canvas.ForceUpdateCanvases();
            threadScroll.verticalNormalizedPosition = 0f;
        }
    }
}
