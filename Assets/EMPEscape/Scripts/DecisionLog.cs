using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using UnityEngine;

namespace EMPEscape
{
    /// <summary>
    /// The player's choices, kept across play sessions in [persistentDataPath]/decisions.json.
    /// Ink records one with "# decision: ray_answer = coming, You told Ray you're coming." (key = value, text).
    /// A later decision with the same key replaces the earlier one. Ink reads them back with the external
    /// function decided("ray_answer"), which returns the value, or "" if that choice was never made.
    /// </summary>
    public static class DecisionLog
    {
        [Serializable]
        public class Decision
        {
            public string key;
            public string value;
            public string text;
            public string scene;
            public string time;
        }

        [Serializable]
        class SaveFile
        {
            public List<Decision> decisions = new List<Decision>();
        }

        static SaveFile data;

        public static event Action Changed;

        static string FilePath => Path.Combine(Application.persistentDataPath, "decisions.json");

        /// <summary>Oldest first.</summary>
        public static IReadOnlyList<Decision> All
        {
            get
            {
                Load();
                return data.decisions;
            }
        }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        static void ResetStatics()
        {
            data = null;
            Changed = null;
        }

        /// <summary>Takes the tag's value: "key = value, text shown in the Choices list". Ink tags can't hold "|".</summary>
        public static void Record(string tagValue)
        {
            var bar = tagValue.IndexOf(',');
            var head = bar < 0 ? tagValue : tagValue.Substring(0, bar);
            var text = bar < 0 ? "" : tagValue.Substring(bar + 1).Trim();
            var equals = head.IndexOf('=');
            var key = (equals < 0 ? head : head.Substring(0, equals)).Trim();
            var value = equals < 0 ? "yes" : head.Substring(equals + 1).Trim();
            if (key.Length == 0)
            {
                Debug.LogWarning($"[DecisionLog] # decision needs a key, like 'ray_answer = coming, text'. Got '{tagValue}'.");
                return;
            }

            Load();
            data.decisions.RemoveAll(d => d.key == key);
            data.decisions.Add(new Decision
            {
                key = key,
                value = value,
                text = text.Length > 0 ? text : $"{key}: {value}",
                scene = UnityEngine.SceneManagement.SceneManager.GetActiveScene().name,
                time = DateTime.Now.ToString("MMM d, h:mm tt", CultureInfo.InvariantCulture),
            });
            Save();
        }

        public static string ValueOf(string key)
        {
            Load();
            var found = data.decisions.Find(d => d.key == key);
            return found != null ? found.value : "";
        }

        public static void Clear()
        {
            Load();
            data.decisions.Clear();
            Save();
        }

        static void Load()
        {
            if (data != null) return;
            try
            {
                data = File.Exists(FilePath) ? JsonUtility.FromJson<SaveFile>(File.ReadAllText(FilePath)) : null;
            }
            catch (Exception e)
            {
                Debug.LogWarning($"[DecisionLog] Couldn't read {FilePath}, starting fresh: {e.Message}");
            }
            if (data == null) data = new SaveFile();
        }

        static void Save()
        {
            try
            {
                File.WriteAllText(FilePath, JsonUtility.ToJson(data, true));
            }
            catch (Exception e)
            {
                Debug.LogWarning($"[DecisionLog] Couldn't save {FilePath}: {e.Message}");
            }
            Changed?.Invoke();
        }
    }
}
