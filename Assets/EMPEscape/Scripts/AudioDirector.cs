using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace EMPEscape
{
    /// <summary>
    /// Plays every sound. Clips load by file name from Resources/Audio (wav, ogg or mp3), so a real recording
    /// replaces a placeholder by taking its name.
    ///   AudioDirector.Play("ui_tap")                      2D one-shot
    ///   AudioDirector.PlayAt("gunshot", position)         one-shot placed in the world
    ///   AudioDirector.SetAmbience("amb_wind, amb_birds")  crossfades to these looping beds ("none" = silence)
    ///   AudioDirector.SetDistant("distant_shot")          random far-off one-shots every 20-50 s ("none" = stop)
    /// From Ink: # sfx: door_bang, # ambience: amb_wind, amb_birds, # distant: distant_shot, distant_crash.
    /// Created on first use; lives for the scene.
    /// </summary>
    public class AudioDirector : MonoBehaviour
    {
        const string Folder = "Audio/";
        const int Voices = 16;
        const float BedFade = 2f;

        static AudioDirector instance;
        static readonly Dictionary<string, AudioClip> Clips = new Dictionary<string, AudioClip>();
        static readonly HashSet<string> Missing = new HashSet<string>();

        public float effectsVolume = 1f;
        public float ambienceVolume = 0.45f;
        public float distantVolume = 0.35f;

        AudioSource[] voices;
        int nextVoice;
        readonly Dictionary<string, AudioSource> beds = new Dictionary<string, AudioSource>();
        string[] distant = new string[0];
        float nextDistant;

        static AudioDirector Instance
        {
            get
            {
                if (instance == null) instance = new GameObject("AudioDirector").AddComponent<AudioDirector>();
                return instance;
            }
        }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        static void ResetStatics()
        {
            instance = null;
            Clips.Clear();
            Missing.Clear();
        }

        void Awake()
        {
            voices = new AudioSource[Voices];
            for (int i = 0; i < Voices; i++)
            {
                var voice = new GameObject("Voice" + i).AddComponent<AudioSource>();
                voice.transform.SetParent(transform, false);
                voice.playOnAwake = false;
                voice.rolloffMode = AudioRolloffMode.Linear;
                voice.minDistance = 4f;
                voice.maxDistance = 40f;
                voices[i] = voice;
            }
        }

        public static AudioClip Load(string name)
        {
            if (string.IsNullOrWhiteSpace(name)) return null;
            name = name.Trim();
            if (Clips.TryGetValue(name, out var clip)) return clip;
            if (Missing.Contains(name)) return null;
            clip = Resources.Load<AudioClip>(Folder + name);
            if (clip == null)
            {
                Missing.Add(name);
                Debug.LogWarning($"[AudioDirector] No sound named '{name}' in Resources/{Folder}.");
                return null;
            }
            Clips[name] = clip;
            return clip;
        }

        public static void Play(string name, float volume = 1f, float pitchJitter = 0f) =>
            Instance.PlayVoice(name, volume, pitchJitter, null, 0f);

        public static void PlayAt(string name, Vector3 position, float volume = 1f, float pitchJitter = 0.04f) =>
            Instance.PlayVoice(name, volume, pitchJitter, position, 0f);

        public static void SetAmbience(string names) => Instance.StartCoroutine(Instance.FadeBeds(Split(names)));

        public static void SetDistant(string names)
        {
            Instance.distant = Split(names);
            Instance.nextDistant = Time.time + Random.Range(8f, 20f);
        }

        void PlayVoice(string name, float volume, float pitchJitter, Vector3? position, float pan)
        {
            var clip = Load(name);
            if (clip == null) return;
            var voice = voices[nextVoice];
            nextVoice = (nextVoice + 1) % voices.Length;

            voice.Stop();
            voice.clip = clip;
            voice.volume = volume * effectsVolume;
            voice.pitch = 1f + Random.Range(-pitchJitter, pitchJitter);
            voice.panStereo = pan;
            // Partly 3D: the camera hears from a distance, so a fully 3D sound would be too quiet.
            voice.spatialBlend = position.HasValue ? 0.7f : 0f;
            voice.transform.position = position ?? Vector3.zero;
            voice.Play();
        }

        IEnumerator FadeBeds(string[] wanted)
        {
            var leaving = new List<AudioSource>();
            foreach (var pair in beds)
                if (System.Array.IndexOf(wanted, pair.Key) < 0) leaving.Add(pair.Value);
            foreach (var source in leaving)
                foreach (var key in new List<string>(beds.Keys))
                    if (beds[key] == source) beds.Remove(key);

            var arriving = new List<AudioSource>();
            foreach (var name in wanted)
            {
                if (beds.ContainsKey(name)) continue;
                var clip = Load(name);
                if (clip == null) continue;
                var source = new GameObject("Bed_" + name).AddComponent<AudioSource>();
                source.transform.SetParent(transform, false);
                source.clip = clip;
                source.loop = true;
                source.volume = 0f;
                source.spatialBlend = 0f;
                source.time = Random.Range(0f, clip.length); // layers don't line up the same way every time
                source.Play();
                beds[name] = source;
                arriving.Add(source);
            }

            for (float t = 0f; t < BedFade; t += Time.unscaledDeltaTime)
            {
                float k = t / BedFade;
                foreach (var source in arriving) if (source != null) source.volume = ambienceVolume * k;
                foreach (var source in leaving) if (source != null) source.volume = Mathf.Min(source.volume, ambienceVolume * (1f - k));
                yield return null;
            }
            foreach (var source in arriving) if (source != null) source.volume = ambienceVolume;
            foreach (var source in leaving) if (source != null) Destroy(source.gameObject);
        }

        void Update()
        {
            if (distant.Length == 0 || Time.time < nextDistant) return;
            nextDistant = Time.time + Random.Range(20f, 50f);
            PlayVoice(distant[Random.Range(0, distant.Length)], distantVolume, 0.08f, null, Random.Range(-0.8f, 0.8f));
        }

        static string[] Split(string names)
        {
            var result = new List<string>();
            foreach (var part in (names ?? "").Split(new[] { ',', ' ' }, System.StringSplitOptions.RemoveEmptyEntries))
                if (!part.Equals("none", System.StringComparison.OrdinalIgnoreCase)) result.Add(part.Trim());
            return result.ToArray();
        }
    }
}
