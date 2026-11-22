using UnityEngine;

namespace EMPEscape
{
    /// <summary>The phone's flashlight: a spotlight from the player's chest, pointing where they face.</summary>
    public class Flashlight : MonoBehaviour
    {
        public static Flashlight Player { get; private set; }

        public float range = 14f;
        public float spotAngle = 60f;
        public float intensity = 8f;

        Light beam;

        public bool IsOn => beam != null && beam.enabled;

        void Awake()
        {
            if (GetComponent<PlayerController>() != null) Player = this;
            beam = new GameObject("Flashlight").AddComponent<Light>();
            beam.transform.SetParent(transform, false);
            beam.transform.localPosition = new Vector3(0.2f, 1.3f, 0.3f);
            beam.transform.localRotation = Quaternion.Euler(12f, 0f, 0f);
            beam.type = LightType.Spot;
            beam.range = range;
            beam.spotAngle = spotAngle;
            beam.intensity = intensity;
            beam.color = new Color(1f, 0.95f, 0.85f);
            beam.shadows = LightShadows.None;
            beam.enabled = false;
        }

        public void Set(bool on)
        {
            if (beam == null || beam.enabled == on) return;
            beam.enabled = on;
            AudioDirector.Play("light_click", 0.8f);
        }

        public void Toggle() => Set(!IsOn);
    }
}
