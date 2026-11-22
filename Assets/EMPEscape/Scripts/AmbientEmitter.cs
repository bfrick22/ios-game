using UnityEngine;

namespace EMPEscape
{
    /// <summary>A looping sound that lives at a spot in the world, such as a burn barrel's crackle.</summary>
    public class AmbientEmitter : MonoBehaviour
    {
        public string sound = "fire_crackle";
        [Range(0f, 1f)] public float volume = 0.8f;
        [Tooltip("Silent beyond this many meters from the camera.")]
        public float range = 28f;

        void Start()
        {
            var clip = AudioDirector.Load(sound);
            if (clip == null) return;
            var source = gameObject.AddComponent<AudioSource>();
            source.clip = clip;
            source.loop = true;
            source.volume = volume;
            source.spatialBlend = 1f;
            source.rolloffMode = AudioRolloffMode.Linear;
            source.minDistance = 3f;
            source.maxDistance = range;
            source.time = Random.Range(0f, clip.length);
            source.Play();
        }
    }
}
