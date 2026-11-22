using System.Collections.Generic;
using UnityEngine;

namespace EMPEscape
{
    /// <summary>
    /// Something worth photographing with the phone. A photo taken with it in view and the player within
    /// range closes the phone and runs its Ink knot, e.g. photographing a manual's pages to load a data pack.
    /// With needsLight, a photo taken without the flashlight runs darkKnot instead.
    /// </summary>
    public class PhotoSubject : MonoBehaviour
    {
        static readonly List<PhotoSubject> All = new List<PhotoSubject>();

        public string knot;
        public bool needsLight;
        public string darkKnot;
        [Tooltip("How close the player must stand, in meters.")]
        public float range = 5f;
        public Transform focus;

        public Vector3 FocusPoint => focus != null ? focus.position : transform.position;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        static void ResetRegistry() => All.Clear();

        void OnEnable() => All.Add(this);
        void OnDisable() => All.Remove(this);

        public string KnotFor(bool flashlightOn) =>
            needsLight && !flashlightOn && !string.IsNullOrEmpty(darkKnot) ? darkKnot : knot;

        /// <summary>The nearest subject on screen and within range of the player, or null.</summary>
        public static PhotoSubject InShot(Camera cam, Vector3 player)
        {
            PhotoSubject best = null;
            float bestDistance = float.MaxValue;
            foreach (var subject in All)
            {
                var view = cam.WorldToViewportPoint(subject.FocusPoint);
                if (view.z <= 0f || view.x < 0.02f || view.x > 0.98f || view.y < 0.02f || view.y > 0.98f) continue;
                float distance = Vector3.Distance(player, subject.FocusPoint);
                if (distance > subject.range || distance >= bestDistance) continue;
                best = subject;
                bestDistance = distance;
            }
            return best;
        }
    }
}
