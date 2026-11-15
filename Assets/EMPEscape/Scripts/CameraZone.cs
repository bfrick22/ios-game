using UnityEngine;

namespace EMPEscape
{
    /// <summary>Trigger volume: when the player walks in, cut to this zone's camera.</summary>
    [RequireComponent(typeof(BoxCollider))]
    public class CameraZone : MonoBehaviour
    {
        public Transform cameraAnchor;

        void Reset() => GetComponent<BoxCollider>().isTrigger = true;

        void OnTriggerEnter(Collider other)
        {
            if (other.GetComponentInParent<PlayerController>() == null) return;
            if (CameraDirector.Instance != null) CameraDirector.Instance.SetGameplayAnchor(cameraAnchor);
        }
    }
}
