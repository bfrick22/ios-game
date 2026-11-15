using System;
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

        Animator animator;
        readonly HashSet<string> parameters = new HashSet<string>();
        Vector3 lastPosition;
        float speed;

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
        }

        public void SetTalking(bool talking)
        {
            if (Has("Talking")) animator.SetBool(TalkingHash, talking);
        }

        /// <summary>Fire a one-shot action trigger, e.g. "flinch" sets the Flinch trigger.</summary>
        public void Play(string action)
        {
            if (string.IsNullOrWhiteSpace(action) || animator == null) return;
            action = action.Trim();
            var trigger = char.ToUpperInvariant(action[0]) + action.Substring(1).ToLowerInvariant();
            if (Has(trigger)) animator.SetTrigger(trigger);
            else Debug.LogWarning($"[CharacterActor] {actorName} has no '{trigger}' animation. Add the clip and rebuild the animator.");
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
