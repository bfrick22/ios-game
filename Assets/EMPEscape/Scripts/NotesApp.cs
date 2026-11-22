using UnityEngine;
using UnityEngine.UI;

namespace EMPEscape
{
    /// <summary>Notes the story writes as things happen (Ink: # note: Ray is heading north at dark.). Newest first.</summary>
    public class NotesApp : PhoneApp
    {
        public override string Title => "Notes";

        ScrollRect scroll;
        RectTransform list;

        protected override void Create()
        {
            scroll = UIFactory.ScrollList("Notes", Page, 14f, out list);
            ((RectTransform)scroll.transform).Stretch();
        }

        public override void Show()
        {
            base.Show();
            for (int i = list.childCount - 1; i >= 0; i--) Object.Destroy(list.GetChild(i).gameObject);
            if (Phone.Notes.Count == 0)
                UIFactory.Paragraph("Empty", list, 26, PhoneUI.DimColor, "No notes yet. Things worth remembering will show up here.");
            for (int i = Phone.Notes.Count - 1; i >= 0; i--)
                UIFactory.Paragraph("Note", list, 28, PhoneUI.TextColor, "- " + Phone.Notes[i]);
            scroll.verticalNormalizedPosition = 1f;
            Phone.MarkNotesRead();
        }
    }
}
