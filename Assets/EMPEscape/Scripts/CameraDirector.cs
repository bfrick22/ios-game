using System.Collections.Generic;
using UnityEngine;

namespace EMPEscape
{
    /// <summary>
    /// Telltale-style fixed cameras. Gameplay cameras sit still and pan a little to follow the player.
    /// Story cameras (# cam: name) are hard cuts to a named anchor and hold still.
    /// </summary>
    [RequireComponent(typeof(Camera))]
    public class CameraDirector : MonoBehaviour
    {
        public static CameraDirector Instance { get; private set; }

        public Transform anchorsRoot;
        public Transform initialAnchor;
        public float maxFollowAngle = 20f;
        public float followSmoothing = 4f;

        readonly Dictionary<string, Transform> anchors = new Dictionary<string, Transform>();
        Transform gameplayAnchor;
        Transform currentAnchor;
        bool following;
        Transform player;

        void Awake()
        {
            Instance = this;
            if (anchorsRoot != null)
                foreach (Transform child in anchorsRoot) anchors[child.name] = child;

            gameplayAnchor = initialAnchor;
            if (gameplayAnchor != null) Snap(gameplayAnchor, true);
        }

        void Start()
        {
            if (PlayerController.Instance != null) player = PlayerController.Instance.transform;
        }

        public void CutTo(string anchorName)
        {
            if (anchors.TryGetValue(anchorName, out var anchor)) Snap(anchor, false);
            else Debug.LogWarning($"[CameraDirector] No camera anchor named '{anchorName}' under {anchorsRoot?.name}.");
        }

        public void SetGameplayAnchor(Transform anchor)
        {
            if (anchor == null || anchor == gameplayAnchor) return;
            gameplayAnchor = anchor;
            if (StoryDirector.Instance == null || !StoryDirector.Instance.IsRunning) Snap(anchor, true);
        }

        public void ReturnToGameplay()
        {
            if (gameplayAnchor != null) Snap(gameplayAnchor, true);
        }

        void Snap(Transform anchor, bool follow)
        {
            currentAnchor = anchor;
            following = follow;
            transform.SetPositionAndRotation(anchor.position, anchor.rotation);
        }

        void LateUpdate()
        {
            if (!following || player == null || currentAnchor == null) return;

            var lookTarget = player.position + Vector3.up * 1.2f - transform.position;
            if (lookTarget.sqrMagnitude < 0.01f) return;

            var desired = Quaternion.RotateTowards(currentAnchor.rotation, Quaternion.LookRotation(lookTarget), maxFollowAngle);
            transform.rotation = Quaternion.Slerp(transform.rotation, desired, 1f - Mathf.Exp(-followSmoothing * Time.deltaTime));
        }
    }
}
