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
    /// Runs Ink knots: shows lines, handles tags (cam, timer, remember, qte, anim, reset, death, end, sfx,
    /// ambience, distant, decision, note), presents choices, and keeps the player's held weapon in step with the
    /// Ink variable "weapon". Binds the Ink function decided(key) to the saved DecisionLog.
    /// World input is locked while a knot runs.
    /// </summary>
    public class StoryDirector : MonoBehaviour
    {
        public static StoryDirector Instance { get; private set; }

        const string WeaponVariable = "weapon";
        static readonly Regex SpeakerLine = new Regex(@"^([A-Z][A-Za-z .'\-]{0,24}):\s*(.+)$");

        [Tooltip("Drag the .ink file here.")]
        public InkFile inkFile;
        public string openingKnot = "intro";

        Story story;
        DialogueUI dialogue;
        QTEController qte;

        public bool IsRunning { get; private set; }

        /// <summary>What the tags of the knot being run asked for.</summary>
        class KnotRun
        {
            public float choiceTimer;
            public QTESpec qte;
            public string end;   // null = no end screen
            public string death; // null = survived
        }

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
            if (HasVariable(WeaponVariable))
                story.ObserveVariable(WeaponVariable, (_, value) => EquipWeapon(value));
            story.BindExternalFunction("decided", (string key) => DecisionLog.ValueOf(key), true);
        }

        void Start()
        {
            dialogue = GameUI.Instance.Dialogue;
            qte = GameUI.Instance.QTE;
            SyncWeapon();
            if (!string.IsNullOrEmpty(openingKnot)) RunKnot(openingKnot);
        }

        /// <summary>Runs a knot. Lines and choices go to the subtitles unless another presenter is given.</summary>
        public void RunKnot(string knot, IStoryPresenter presenter = null)
        {
            if (IsRunning) return;
            StartCoroutine(Run(knot, presenter ?? dialogue));
        }

        IEnumerator Run(string knot, IStoryPresenter presenter)
        {
            IsRunning = true;
            GameInput.Lock();
            GameUI.Instance.HotspotMenu.Hide();
            PlayerController.Instance.Stop();

            var checkpoint = story.state.ToJson(); // for Retry after a death
            story.ChoosePathString(knot);
            var run = new KnotRun();

            while (true)
            {
                while (story.canContinue)
                {
                    var line = story.Continue().Trim();
                    HandleTags(story.currentTags, run);
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
                    yield return presenter.ShowLine(speaker, line);
                    if (actor != null) actor.SetTalking(false);
                }

                var choices = story.currentChoices;
                if (choices.Count == 0) break;

                if (run.qte != null)
                {
                    bool success = false;
                    yield return qte.Run(run.qte, result => success = result);
                    run.qte = null;
                    story.ChooseChoiceIndex(FindChoice(choices, success ? "success" : "fail"));
                    continue;
                }

                int picked = -1;
                yield return presenter.ShowChoices(choices, run.choiceTimer, index => picked = index);
                run.choiceTimer = 0f;
                story.ChooseChoiceIndex(picked);
            }

            presenter.HideLine();
            CameraDirector.Instance.ReturnToGameplay();

            if (run.death != null)
            {
                // Stays locked until Retry.
                dialogue.ShowDeath(run.death.Length > 0 ? run.death : "You died.", () => Retry(knot, checkpoint));
                yield break;
            }
            if (run.end != null)
            {
                dialogue.ShowEndScreen(run.end.Length > 0 ? run.end : "End of test slice");
                yield break; // stays locked; Restart reloads the scene
            }

            GameInput.Unlock();
            IsRunning = false;
        }

        void Retry(string knot, string checkpoint)
        {
            story.state.LoadJson(checkpoint);
            SyncWeapon();
            IsRunning = false;
            GameInput.Unlock();
            RunKnot(knot);
        }

        void HandleTags(List<string> tags, KnotRun run)
        {
            foreach (var tag in tags)
            {
                var split = tag.IndexOf(':');
                var key = (split < 0 ? tag : tag.Substring(0, split)).Trim().ToLowerInvariant();
                var value = split < 0 ? "" : tag.Substring(split + 1).Trim();

                switch (key)
                {
                    case "cam": CameraDirector.Instance.CutTo(value); break;
                    case "timer": float.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out run.choiceTimer); break;
                    case "remember": dialogue.ShowRemember(value); break;
                    case "qte": run.qte = QTESpec.Parse(value); break;
                    case "anim": PlayAnimation(value); break;
                    case "reset": ShootTarget.ResetGroup(value); break;
                    case "death": run.death = value; break;
                    case "end": run.end = value; break;
                    case "sfx": AudioDirector.Play(value); break;
                    case "ambience": AudioDirector.SetAmbience(value); break;
                    case "distant": AudioDirector.SetDistant(value); break;
                    case "decision": DecisionLog.Record(value); break;
                    case "note": if (PhoneUI.Instance != null) PhoneUI.Instance.AddNote(value); break;
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

        void SyncWeapon()
        {
            if (HasVariable(WeaponVariable)) EquipWeapon(story.variablesState[WeaponVariable]);
        }

        static void EquipWeapon(object value)
        {
            var holder = WeaponHolder.Player;
            if (holder != null) holder.Equip(value == null ? "none" : value.ToString());
        }

        public bool HasVariable(string name) => story != null && story.variablesState.GlobalVariableExistsWithName(name);

        /// <summary>An Ink true/false variable, or false if the story doesn't declare it.</summary>
        public bool GetFlag(string variable) => HasVariable(variable) && GetBool(variable);

        /// <summary>Game code writing story state, e.g. the device's battery. Ignored if the story doesn't declare it.</summary>
        public void SetInt(string variable, int value)
        {
            if (HasVariable(variable)) story.variablesState[variable] = value;
        }

        /// <summary>Read an Ink variable from game code, e.g. GetInt("ray_trust").</summary>
        public int GetInt(string variable) => System.Convert.ToInt32(story.variablesState[variable]);
        public bool GetBool(string variable) => System.Convert.ToBoolean(story.variablesState[variable]);
        public string GetString(string variable) => story.variablesState[variable]?.ToString() ?? "";
    }
}
