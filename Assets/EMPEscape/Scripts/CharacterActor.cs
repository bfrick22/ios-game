using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace EMPEscape
{
    /// <summary>
    /// A named character the story can drive. Feeds walk speed to the Animator, turns talking on while
    /// the character's lines show, and plays one-shot actions from Ink ("# anim: Ray flinch").
    /// Works without an Animator (placeholder capsules simply don't animate).
    /// Animator parameters it uses when present: Speed (float), Talking (bool), and one trigger per action (Flinch, ...).
    /// </summary>
    public class CharacterActor : MonoBehaviour
    {
        static readonly Dictionary<string, CharacterActor> Actors = new Dictionary<string, CharacterActor>(StringComparer.OrdinalIgnoreCase);
        static readonly int SpeedHash = Animator.StringToHash("Speed");
        static readonly int TalkingHash = Animator.StringToHash("Talking");

        [Tooltip("Must match the speaker name used in Ink (\"Ray: ...\") and in # anim tags.")]
        public string actorName = "Actor";
        public float speedSmoothing = 10f;
        [Tooltip("Play footstep sounds while walking (the scene builder turns this on for the player).")]
        public bool footsteps;
        public float strideLength = 0.75f;

        Animator animator;
        readonly HashSet<string> parameters = new HashSet<string>();
        readonly HashSet<string> warned = new HashSet<string>();
        Vector3 lastPosition;
        float speed;
        float stride;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        static void ResetRegistry() => Actors.Clear();

        public static CharacterActor Find(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return null;
            return Actors.TryGetValue(name.Trim(), out var actor) ? actor : null;
        }

        void Awake()
        {
            animator = GetComponentInChildren<Animator>();
            if (animator != null && animator.runtimeAnimatorController != null)
                foreach (var parameter in animator.parameters) parameters.Add(parameter.name);
            lastPosition = transform.position;
        }

        void OnEnable() => Actors[actorName] = this;

        void OnDisable()
        {
            if (Actors.TryGetValue(actorName, out var actor) && actor == this) Actors.Remove(actorName);
        }

        void Update()
        {
            var delta = transform.position - lastPosition;
            delta.y = 0f;
            lastPosition = transform.position;

            float raw = Time.deltaTime > 0f ? delta.magnitude / Time.deltaTime : 0f;
            speed = Mathf.Lerp(speed, raw, 1f - Mathf.Exp(-speedSmoothing * Time.deltaTime));
            if (Has("Speed")) animator.SetFloat(SpeedHash, speed);

            if (!footsteps || speed < 0.4f) return;
            stride += delta.magnitude;
            if (stride < strideLength) return;
            stride = 0f;
            AudioDirector.PlayAt("step_" + UnityEngine.Random.Range(1, 5), transform.position, 0.45f, 0.07f);
        }

        public void SetTalking(bool talking)
        {
            if (Has("Talking")) animator.SetBool(TalkingHash, talking);
        }

        /// <summary>
        /// Fire a one-shot action trigger, e.g. "flinch" sets the Flinch trigger. Without that clip a
        /// flinch still shows as a quick wobble, so placeholders react to hits.
        /// </summary>
        public void Play(string action)
        {
            if (string.IsNullOrWhiteSpace(action)) return;
            action = action.Trim();
            var trigger = char.ToUpperInvariant(action[0]) + action.Substring(1).ToLowerInvariant();
            if (Has(trigger))
            {
                animator.SetTrigger(trigger);
                return;
            }
            if (trigger == "Flinch") StartCoroutine(Wobble());
            if (animator != null && warned.Add(trigger))
                Debug.LogWarning($"[CharacterActor] {actorName} has no '{trigger}' animation. Add the clip and run Build Character Animator.");
        }

        IEnumerator Wobble()
        {
            Transform visual = null;
            foreach (Transform child in transform)
                if (child.name.StartsWith("Visual")) { visual = child; break; }
            if (visual == null) yield break;

            var rest = visual.localRotation;
            var tilted = rest * Quaternion.Euler(-14f, 0f, 0f);
            for (float t = 0f; t < 0.07f; t += Time.deltaTime) { visual.localRotation = Quaternion.Slerp(rest, tilted, t / 0.07f); yield return null; }
            for (float t = 0f; t < 0.25f; t += Time.deltaTime) { visual.localRotation = Quaternion.Slerp(tilted, rest, t / 0.25f); yield return null; }
            visual.localRotation = rest;
        }

        public void FaceTowards(Vector3 point)
        {
            var direction = point - transform.position;
            direction.y = 0f;
            if (direction.sqrMagnitude > 0.001f) transform.rotation = Quaternion.LookRotation(direction);
        }

        bool Has(string parameter) => animator != null && parameters.Contains(parameter);
    }
}
