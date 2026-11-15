using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Text.RegularExpressions;
using Ink.Runtime;
using Ink.UnityIntegration;
using UnityEngine;

namespace EMPEscape
{
    /// <summary>
    /// Runs Ink knots: shows lines, handles tags (cam, timer, remember, qte, end), presents choices.
    /// World input is locked while a knot runs.
    /// </summary>
    public class StoryDirector : MonoBehaviour
    {
        public static StoryDirector Instance { get; private set; }

        [Tooltip("Drag the .ink file here.")]
        public InkFile inkFile;
        public string openingKnot = "intro";

        static readonly Regex SpeakerLine = new Regex(@"^([A-Z][A-Za-z .'\-]{0,24}):\s*(.+)$");

        Story story;
        DialogueUI dialogue;
        QTEController qte;

        public bool IsRunning { get; private set; }

        void Awake()
        {
            Instance = this;
            if (inkFile == null || !inkFile.isCompiled)
            {
                Debug.LogError("[StoryDirector] Ink file missing or not compiled. Select the .ink file and check the Inspector for errors.");
                enabled = false;
                return;
            }
            story = new Story(inkFile.storyJson);
        }

        void Start()
        {
            dialogue = GameUI.Instance.Dialogue;
            qte = GameUI.Instance.QTE;
            if (!string.IsNullOrEmpty(openingKnot)) RunKnot(openingKnot);
        }

        public void RunKnot(string knot)
        {
            if (IsRunning) return;
            StartCoroutine(Run(knot));
        }

        IEnumerator Run(string knot)
        {
            IsRunning = true;
            GameInput.Lock();
            GameUI.Instance.HotspotMenu.Hide();
            PlayerController.Instance.Stop();

            story.ChoosePathString(knot);

            float choiceTimer = 0f;
            QTESpec pendingQte = null;
            bool endOfSlice = false;

            while (true)
            {
                while (story.canContinue)
                {
                    var line = story.Continue().Trim();
                    HandleTags(story.currentTags, ref choiceTimer, ref pendingQte, ref endOfSlice);
                    if (line.Length == 0) continue;

                    string speaker = null;
                    var match = SpeakerLine.Match(line);
                    if (match.Success)
                    {
                        speaker = match.Groups[1].Value;
                        line = match.Groups[2].Value;
                    }
                    var actor = CharacterActor.Find(speaker);
                    if (actor != null) actor.SetTalking(true);
                    yield return dialogue.ShowLine(speaker, line);
                    if (actor != null) actor.SetTalking(false);
                }

                var choices = story.currentChoices;
                if (choices.Count == 0) break;

                if (pendingQte != null)
                {
                    bool success = false;
                    yield return qte.Run(pendingQte, result => success = result);
                    pendingQte = null;
                    story.ChooseChoiceIndex(FindChoice(choices, success ? "success" : "fail"));
                    continue;
                }

                int picked = -1;
                yield return dialogue.ShowChoices(choices, choiceTimer, index => picked = index);
                choiceTimer = 0f;
                story.ChooseChoiceIndex(picked);
            }

            dialogue.HideLine();
            CameraDirector.Instance.ReturnToGameplay();

            if (endOfSlice)
            {
                dialogue.ShowEndScreen("End of test slice");
                yield break; // stays locked; Restart reloads the scene
            }

            GameInput.Unlock();
            IsRunning = false;
        }

        void HandleTags(List<string> tags, ref float choiceTimer, ref QTESpec pendingQte, ref bool endOfSlice)
        {
            foreach (var tag in tags)
            {
                var split = tag.IndexOf(':');
                var key = (split < 0 ? tag : tag.Substring(0, split)).Trim().ToLowerInvariant();
                var value = split < 0 ? "" : tag.Substring(split + 1).Trim();

                switch (key)
                {
                    case "cam": CameraDirector.Instance.CutTo(value); break;
                    case "timer": float.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out choiceTimer); break;
                    case "remember": dialogue.ShowRemember(value); break;
                    case "qte": pendingQte = QTESpec.Parse(value); break;
                    case "end": endOfSlice = true; break;
                    case "anim": PlayAnimation(value); break;
                    default: Debug.LogWarning($"[StoryDirector] Unknown Ink tag '{tag}'."); break;
                }
            }
        }

        /// <summary>"# anim: Ray flinch" fires the Flinch trigger on the actor named Ray.</summary>
        static void PlayAnimation(string value)
        {
            var split = value.IndexOf(' ');
            if (split <= 0)
            {
                Debug.LogWarning($"[StoryDirector] # anim needs an actor and an action, e.g. '# anim: Ray flinch'. Got '{value}'.");
                return;
            }
            var actorName = value.Substring(0, split);
            var actor = CharacterActor.Find(actorName);
            if (actor == null) Debug.LogWarning($"[StoryDirector] No CharacterActor named '{actorName}' in the scene.");
            else actor.Play(value.Substring(split + 1));
        }

        static int FindChoice(List<Choice> choices, string text)
        {
            for (int i = 0; i < choices.Count; i++)
                if (string.Equals(choices[i].text.Trim(), text, System.StringComparison.OrdinalIgnoreCase)) return i;
            Debug.LogWarning($"[StoryDirector] QTE needs a [{text}] choice; picking the first one.");
            return 0;
        }

        /// <summary>Read an Ink variable from game code, e.g. GetInt("ray_trust").</summary>
        public int GetInt(string variable) => System.Convert.ToInt32(story.variablesState[variable]);
        public bool GetBool(string variable) => System.Convert.ToBoolean(story.variablesState[variable]);
    }
}
