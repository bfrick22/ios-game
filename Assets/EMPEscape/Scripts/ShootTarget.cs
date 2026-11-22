using System.Collections;
using System.Collections.Generic;
using UnityEngine;

namespace EMPEscape
{
    /// <summary>
    /// Something the shoot QTE can hit. All targets sharing a group are the goal of one QTE
    /// ("# qte: shoot 7 range"). A hit tints it red and tips it over backward. Each shoot QTE stands its
    /// group back up first; Ink can also do it with "# reset: range".
    /// </summary>
    public class ShootTarget : MonoBehaviour
    {
        static readonly List<ShootTarget> All = new List<ShootTarget>();
        static readonly int BaseColorId = Shader.PropertyToID("_BaseColor");
        static readonly int ColorId = Shader.PropertyToID("_Color");

        public string group = "range";
        [Tooltip("Where the reticle has to be. Defaults to 1.3 m above this object.")]
        public Transform aimPoint;
        public float fallAngle = 80f;
        public float fallTime = 0.25f;
        [Tooltip("Sound when hit: target_hit for metal plates, hit_flesh for people.")]
        public string hitSound = "target_hit";

        public bool IsDown { get; private set; }
        public Vector3 AimPosition => aimPoint != null ? aimPoint.position : transform.position + Vector3.up * 1.3f;

        Quaternion standing;
        Renderer[] renderers;
        MaterialPropertyBlock block;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.SubsystemRegistration)]
        static void ResetRegistry() => All.Clear();

        public static List<ShootTarget> InGroup(string group)
        {
            var result = new List<ShootTarget>();
            foreach (var target in All)
                if (string.Equals(target.group, group, System.StringComparison.OrdinalIgnoreCase)) result.Add(target);
            return result;
        }

        public static void ResetGroup(string group)
        {
            foreach (var target in InGroup(group)) target.ResetTarget();
        }

        void Awake()
        {
            standing = transform.localRotation;
            renderers = GetComponentsInChildren<Renderer>();
            block = new MaterialPropertyBlock();
        }

        void OnEnable() => All.Add(this);
        void OnDisable() => All.Remove(this);

        public void Hit()
        {
            if (IsDown) return;
            IsDown = true;
            AudioDirector.PlayAt(hitSound, AimPosition);
            standing = transform.localRotation; // stand back up facing the way it was hit
            Tint(new Color(0.85f, 0.15f, 0.12f));
            StopAllCoroutines();
            StartCoroutine(Fall());
        }

        public void ResetTarget()
        {
            StopAllCoroutines();
            if (IsDown) transform.localRotation = standing;
            IsDown = false;
            foreach (var r in renderers) r.SetPropertyBlock(null);
        }

        IEnumerator Fall()
        {
            var from = transform.localRotation;
            var to = standing * Quaternion.Euler(-fallAngle, 0f, 0f); // top tips toward its back
            for (float t = 0f; t < fallTime; t += Time.deltaTime)
            {
                float k = t / fallTime;
                transform.localRotation = Quaternion.Slerp(from, to, k * k);
                yield return null;
            }
            transform.localRotation = to;
        }

        void Tint(Color color)
        {
            foreach (var r in renderers)
            {
                r.GetPropertyBlock(block);
                block.SetColor(BaseColorId, color);
                block.SetColor(ColorId, color);
                r.SetPropertyBlock(block);
            }
        }
    }
}
