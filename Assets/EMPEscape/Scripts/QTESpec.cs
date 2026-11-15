using System.Globalization;
using UnityEngine;

namespace EMPEscape
{
    public enum QTEType { Tap, Mash, Hold }

    /// <summary>Parsed from an Ink tag: "# qte: tap 1.5" | "# qte: mash 3 8" | "# qte: hold 3 1.5".</summary>
    public class QTESpec
    {
        public QTEType type = QTEType.Tap;
        public float window = 2f;   // seconds the player has
        public float amount = 1f;   // mash: presses needed; hold: seconds to hold

        public static QTESpec Parse(string value)
        {
            var spec = new QTESpec();
            var parts = value.Split(new[] { ' ' }, System.StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length > 0)
            {
                switch (parts[0].ToLowerInvariant())
                {
                    case "mash": spec.type = QTEType.Mash; spec.amount = 8f; break;
                    case "hold": spec.type = QTEType.Hold; spec.amount = 1.5f; break;
                    case "tap": spec.type = QTEType.Tap; break;
                    default: Debug.LogWarning($"[QTESpec] Unknown QTE type '{parts[0]}', using tap."); break;
                }
            }
            if (parts.Length > 1) float.TryParse(parts[1], NumberStyles.Float, CultureInfo.InvariantCulture, out spec.window);
            if (parts.Length > 2) float.TryParse(parts[2], NumberStyles.Float, CultureInfo.InvariantCulture, out spec.amount);
            return spec;
        }
    }
}
