using System.Collections.Generic;
using UnityEngine;

namespace EMPEscape
{
    /// <summary>
    /// Trigger volume: while the player is inside, its camera is used. Zones can nest (a shed inside a yard
    /// zone): the zone entered most recently wins, and leaving it hands the camera back to the zone around it.
    /// </summary>
    [RequireComponent(typeof(BoxCollider))]
    public class CameraZone : MonoBehaviour
    {
        static readonly List<CameraZone> Occupied = new List<CameraZone>();

        public Transform cameraAnchor;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        static void ResetStatics() => Occupied.Clear();

        void Reset() => GetComponent<BoxCollider>().isTrigger = true;

        void OnDisable() => Occupied.Remove(this);

        void OnTriggerEnter(Collider other)
        {
            if (other.GetComponentInParent<PlayerController>() == null) return;
            Occupied.Remove(this);
            Occupied.Add(this);
            Apply();
        }

        void OnTriggerExit(Collider other)
        {
            if (other.GetComponentInParent<PlayerController>() == null) return;
            Occupied.Remove(this);
            Apply();
        }

        static void Apply()
        {
            if (Occupied.Count == 0 || CameraDirector.Instance == null) return;
            CameraDirector.Instance.SetGameplayAnchor(Occupied[Occupied.Count - 1].cameraAnchor);
        }
    }
}
