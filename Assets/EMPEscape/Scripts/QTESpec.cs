using System.Globalization;
using UnityEngine;

namespace EMPEscape
{
    public enum QTEType { Tap, Mash, Hold, Shoot, Swing }

    /// <summary>
    /// Parsed from an Ink "# qte:" tag:
    ///   tap   [window]                          # qte: tap 1.5
    ///   mash  [window] [presses]                # qte: mash 3 8
    ///   hold  [window] [seconds held]           # qte: hold 3 1.5
    ///   shoot [window] [target group]           # qte: shoot 7 range
    ///   swing [window per swing] [swings] [actor hit]   # qte: swing 1.2 3 Dummy
    /// </summary>
    public class QTESpec
    {
        public QTEType type = QTEType.Tap;
        public float window = 2f;    // seconds (per swing for swing)
        public float amount = 1f;    // mash: presses; hold: seconds; swing: number of swings
        public string targetGroup = "";
        public string actor = "";

        public static QTESpec Parse(string value)
        {
            var spec = new QTESpec();
            var parts = value.Split(new[] { ' ' }, System.StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length > 0)
            {
                switch (parts[0].ToLowerInvariant())
                {
                    case "tap": spec.type = QTEType.Tap; break;
                    case "mash": spec.type = QTEType.Mash; spec.amount = 8f; break;
                    case "hold": spec.type = QTEType.Hold; spec.amount = 1.5f; break;
                    case "shoot": spec.type = QTEType.Shoot; spec.window = 6f; break;
                    case "swing": spec.type = QTEType.Swing; spec.window = 1.2f; spec.amount = 3f; break;
                    default: Debug.LogWarning($"[QTESpec] Unknown QTE type '{parts[0]}', using tap."); break;
                }
            }
            if (parts.Length > 1) float.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out spec.window);

            if (spec.type == QTEType.Shoot)
            {
                if (parts.Length > 2) spec.targetGroup = parts[2];
                return spec;
            }
            if (parts.Length > 2) float.TryParse(parts[2], NumberStyles.Float, CultureInfo.InvariantCulture, out spec.amount);
            if (spec.type == QTEType.Swing && parts.Length > 3) spec.actor = parts[3];
            return spec;
        }
    }
}
