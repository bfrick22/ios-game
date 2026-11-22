using UnityEngine;

namespace EMPEscape
{
    /// <summary>
    /// What the player holds. Ink's "weapon" variable drives it ("none", "knife", "bat", "pistol");
    /// StoryDirector watches the variable and calls Equip. The scene builder makes one inactive prop per
    /// weapon, named after it. At start the props move to the right-hand bone (or a hand point on
    /// placeholder capsules). To fix a prop's angle in the hand: tweak gripPosition / gripRotation here
    /// in Play mode, then copy the values to Weapon Grip in Assets/EMPEscape/Art/SliceArtSet.
    /// </summary>
    public class WeaponHolder : MonoBehaviour
    {
        public static WeaponHolder Player { get; private set; }
        public static string PlayerWeapon => Player != null ? Player.Current : "none";

        public GameObject[] props = new GameObject[0];
        [Tooltip("Prop offset in the hand bone's space (humanoid characters only).")]
        public Vector3 gripPosition;
        public Vector3 gripRotation;

        public string Current { get; private set; } = "none";

        Transform hand;
        bool onBone;
        GameObject held;

        void Awake()
        {
            if (GetComponent<PlayerController>() != null) Player = this;
        }

        void Start()
        {
            hand = FindHand();
            foreach (var prop in props)
            {
                if (prop == null) continue;
                prop.transform.SetParent(hand, true); // keep world size; the model may be scaled
                prop.SetActive(prop == held);
            }
            ApplyGrip();
        }

        Transform FindHand()
        {
            var animator = GetComponentInChildren<Animator>();
            if (animator != null && animator.isHuman)
            {
                var bone = animator.GetBoneTransform(HumanBodyBones.RightHand);
                if (bone != null)
                {
                    onBone = true;
                    return bone;
                }
            }
            var point = new GameObject("HandPoint").transform;
            point.SetParent(transform, false);
            point.localPosition = new Vector3(0.38f, 1.0f, 0.2f);
            return point;
        }

        public void Equip(string weapon)
        {
            weapon = string.IsNullOrWhiteSpace(weapon) ? "none" : weapon.Trim().ToLowerInvariant();
            if (weapon == Current) return;
            Current = weapon;

            held = null;
            foreach (var prop in props)
            {
                if (prop == null) continue;
                bool match = prop.name == weapon;
                prop.SetActive(match);
                if (match) held = prop;
            }
            if (held == null && weapon != "none") Debug.LogWarning($"[WeaponHolder] No prop named '{weapon}'.");

            ApplyGrip();
            if (GameUI.Instance != null) GameUI.Instance.SetWeapon(weapon == "none" ? "" : weapon);
        }

        // Re-applied every frame while held so grip values can be tuned live in Play mode.
        void LateUpdate()
        {
            if (held != null) ApplyGrip();
        }

        void ApplyGrip()
        {
            if (hand == null) return;
            var position = onBone ? gripPosition : Vector3.zero;
            var rotation = onBone ? Quaternion.Euler(gripRotation) : Quaternion.identity;
            foreach (var prop in props)
            {
                if (prop == null) continue;
                prop.transform.localPosition = position;
                prop.transform.localRotation = rotation;
            }
        }
    }
}
