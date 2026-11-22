using System;
using System.Collections.Generic;
using UnityEngine;

namespace EMPEscape
{
    /// <summary>
    /// The phone's survival data: preset questions and answers for Field-AI, and topics for the Guide app.
    /// Lives in Resources/FieldGuide/fieldguide.json. Each entry belongs to a data pack; "core" is always
    /// loaded and any other pack is loaded when the Ink flag pack_[id] is true (e.g. ~ pack_medical = true).
    /// </summary>
    public class FieldGuide
    {
        [Serializable]
        public class Pack
        {
            public string id;
            public string name;
            public string howToGet;
        }

        [Serializable]
        public class Entry
        {
            public string id;
            public string pack;
            public string category;
            public string title;
            public string question;
            public string answer;
            public string details;
        }

        [Serializable]
        class FileData
        {
            public Pack[] packs = new Pack[0];
            public Entry[] entries = new Entry[0];
        }

        const string ResourcePath = "FieldGuide/fieldguide";

        public IReadOnlyList<Pack> Packs => data.packs;
        public IReadOnlyList<Entry> Entries => data.entries;

        readonly FileData data;

        FieldGuide(FileData data) => this.data = data;

        public static FieldGuide Load()
        {
            var asset = Resources.Load<TextAsset>(ResourcePath);
            if (asset == null)
            {
                Debug.LogWarning($"[FieldGuide] Missing Resources/{ResourcePath}.json.");
                return new FieldGuide(new FileData());
            }
            try
            {
                return new FieldGuide(JsonUtility.FromJson<FileData>(asset.text) ?? new FileData());
            }
            catch (Exception e)
            {
                Debug.LogError($"[FieldGuide] {ResourcePath}.json is not valid JSON: {e.Message}");
                return new FieldGuide(new FileData());
            }
        }

        public static bool IsLoaded(string pack)
        {
            if (string.IsNullOrEmpty(pack) || pack == "core") return true;
            return StoryDirector.Instance != null && StoryDirector.Instance.GetFlag("pack_" + pack);
        }

        public bool IsLoaded(Entry entry) => IsLoaded(entry.pack);

        public Pack FindPack(string id)
        {
            foreach (var pack in data.packs)
                if (pack.id == id) return pack;
            return new Pack { id = id, name = id, howToGet = "" };
        }
    }
}
