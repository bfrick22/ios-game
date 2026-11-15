using UnityEngine;
using UnityEngine.AI;

namespace EMPEscape
{
    public enum HotspotVerb { Look, Use, Talk }

    /// <summary>Something the player can tap. Each verb runs an Ink knot; leave a knot empty to hide that verb.</summary>
    public class Hotspot : MonoBehaviour
    {
        public string displayName = "Object";
        public string lookKnot;
        public string useKnot;
        public string talkKnot;

        [Tooltip("Where the player stands to Use/Talk. Defaults to the nearest NavMesh point to this object.")]
        public Transform standPoint;

        public bool Has(HotspotVerb verb) => !string.IsNullOrEmpty(KnotFor(verb));

        public string KnotFor(HotspotVerb verb)
        {
            switch (verb)
            {
                case HotspotVerb.Look: return lookKnot;
                case HotspotVerb.Use: return useKnot;
                default: return talkKnot;
            }
        }

        public void Interact(HotspotVerb verb)
        {
            var knot = KnotFor(verb);
            if (string.IsNullOrEmpty(knot)) return;

            var player = PlayerController.Instance;

            // Look happens from where you stand, like Telltale. Use/Talk walk over first.
            if (verb == HotspotVerb.Look)
            {
                player.Stop();
                player.FaceTowards(transform.position);
                StoryDirector.Instance.RunKnot(knot);
                return;
            }

            var target = standPoint != null ? standPoint.position : transform.position;
            if (NavMesh.SamplePosition(target, out var navHit, 3f, NavMesh.AllAreas)) target = navHit.position;

            GameInput.Lock();
            player.MoveTo(target, () =>
            {
                GameInput.Unlock();
                player.FaceTowards(transform.position);
                // Characters turn to face you when you talk to them.
                var actor = GetComponent<CharacterActor>();
                if (actor != null && verb == HotspotVerb.Talk) actor.FaceTowards(player.transform.position);
                StoryDirector.Instance.RunKnot(knot);
            });
        }
    }
}
