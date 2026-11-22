using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace EMPEscape
{
    /// <summary>Guide: browse the field guide by category and read a topic. Topics from unloaded packs are listed but locked.</summary>
    public class GuideApp : PhoneApp
    {
        public override string Title => "Guide";

        ScrollRect listScroll;
        RectTransform list;
        ScrollRect readerScroll;
        Text reader;

        protected override void Create()
        {
            listScroll = UIFactory.ScrollList("Topics", Page, 8f, out list);
            ((RectTransform)listScroll.transform).Stretch();
            readerScroll = UIFactory.ScrollList("Reader", Page, 0f, out var readerContent);
            ((RectTransform)readerScroll.transform).Stretch();
            reader = UIFactory.Paragraph("Text", readerContent, 28, PhoneUI.TextColor, "");
        }

        public override void Show()
        {
            base.Show();
            ShowList();
        }

        public override bool Back()
        {
            if (!readerScroll.gameObject.activeSelf) return false;
            ShowList();
            return true;
        }

        void ShowList()
        {
            readerScroll.gameObject.SetActive(false);
            listScroll.gameObject.SetActive(true);
            for (int i = list.childCount - 1; i >= 0; i--) Object.Destroy(list.GetChild(i).gameObject);

            var guide = Phone.Guide;
            var packs = new List<string>();
            foreach (var pack in guide.Packs)
                packs.Add(FieldGuide.IsLoaded(pack.id) ? pack.name : $"<color=#6e7681>{pack.name} (not loaded)</color>");
            UIFactory.Paragraph("Packs", list, 22, PhoneUI.DimColor, "DATA: " + string.Join(",  ", packs));

            var categories = new List<string>();
            foreach (var entry in guide.Entries)
                if (!categories.Contains(entry.category)) categories.Add(entry.category);

            foreach (var category in categories)
            {
                UIFactory.Paragraph("Category", list, 24, PhoneUI.Accent, "\n" + category.ToUpperInvariant());
                foreach (var entry in guide.Entries)
                {
                    if (entry.category != category) continue;
                    var button = UIFactory.ListButton("Topic", list, 27, 66f, out var label);
                    label.text = guide.IsLoaded(entry) ? entry.title : $"<color=#6e7681>{entry.title}   NOT LOADED</color>";
                    var chosen = entry;
                    button.onClick.AddListener(() => ShowEntry(chosen));
                }
            }
            listScroll.verticalNormalizedPosition = 1f;
        }

        void ShowEntry(FieldGuide.Entry entry)
        {
            listScroll.gameObject.SetActive(false);
            readerScroll.gameObject.SetActive(true);
            var guide = Phone.Guide;
            var pack = guide.FindPack(entry.pack);
            var heading = $"<b><size=34>{entry.title}</size></b>\n<size=22><color=#8b949e>{entry.category}  ·  {pack.name}</color></size>\n\n";
            reader.text = guide.IsLoaded(entry)
                ? heading + entry.answer + (string.IsNullOrEmpty(entry.details) ? "" : "\n\n" + entry.details)
                : heading + $"NOT LOADED.\n\nThis topic is in the {pack.name} data. {pack.howToGet}";
            readerScroll.verticalNormalizedPosition = 1f;
        }
    }
}
