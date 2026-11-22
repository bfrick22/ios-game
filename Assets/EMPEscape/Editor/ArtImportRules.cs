using System.IO;
using UnityEditor;
using UnityEngine;

namespace EMPEscape.EditorTools
{
    /// <summary>
    /// Import defaults for EMP Escape art, applied the first time a file is imported (your later
    /// Inspector changes stick):
    ///   Art/Characters/*  -> Humanoid rig, avatar from the model
    ///   Art/Animations/*  -> Humanoid rig; a single clip is named after its file; clips with idle/walk/talk/run
    ///                        in the name loop with Loop Pose on
    /// Root motion: rotation and height are baked into the pose, but forward/sideways motion (XZ) is NOT.
    /// It is pulled out to the root, which the game ignores (applyRootMotion is off), so a walk that wasn't
    /// downloaded "In Place" still stays on the spot instead of drifting ahead and snapping back each loop.
    /// Menu: EMP Escape > Reapply Animation Import Settings re-applies these to every file in Art/Animations.
    /// </summary>
    public class ArtImportRules : AssetPostprocessor
    {
        public const string CharactersDir = "Assets/EMPEscape/Art/Characters/";
        public const string AnimationsDir = "Assets/EMPEscape/Art/Animations/";
        static readonly string[] LoopingKeywords = { "idle", "walk", "talk", "run" };

        void OnPreprocessModel()
        {
            if (!IsCharacterOrAnimation() || !assetImporter.importSettingsMissing) return;
            var importer = (ModelImporter)assetImporter;
            importer.animationType = ModelImporterAnimationType.Human;
            importer.avatarSetup = ModelImporterAvatarSetup.CreateFromThisModel;
            importer.importAnimation = assetPath.StartsWith(AnimationsDir);
        }

        void OnPreprocessAnimation()
        {
            if (!assetPath.StartsWith(AnimationsDir) || !assetImporter.importSettingsMissing) return;
            var importer = (ModelImporter)assetImporter;
            importer.clipAnimations = ApplyClipRules(importer.defaultClipAnimations, assetPath);
        }

        /// <summary>Overwrites the clip settings of every file in Art/Animations with the rules above, then reimports.</summary>
        [MenuItem("EMP Escape/Reapply Animation Import Settings")]
        static void ReapplyToAnimations()
        {
            int count = 0;
            foreach (var guid in AssetDatabase.FindAssets("t:Model", new[] { AnimationsDir.TrimEnd('/') }))
            {
                var path = AssetDatabase.GUIDToAssetPath(guid);
                if (!(AssetImporter.GetAtPath(path) is ModelImporter importer)) continue;
                var clips = importer.clipAnimations;
                if (clips == null || clips.Length == 0) clips = importer.defaultClipAnimations;
                importer.clipAnimations = ApplyClipRules(clips, path);
                importer.SaveAndReimport();
                count++;
            }
            Debug.Log($"[EMP Escape] Reapplied animation import settings to {count} file(s) in {AnimationsDir}.");
        }

        static ModelImporterClipAnimation[] ApplyClipRules(ModelImporterClipAnimation[] clips, string path)
        {
            var fileName = Path.GetFileNameWithoutExtension(path);
            for (int i = 0; i < clips.Length; i++)
            {
                // One clip per file (Mixamo): name it after the file. Many clips per file (animation libraries): keep their names.
                if (clips.Length == 1) clips[i].name = fileName;
                bool loop = ContainsAny(clips[i].name.ToLowerInvariant(), LoopingKeywords);
                clips[i].loopTime = loop;
                clips[i].loopPose = loop;              // blend the last frame into the first, so the seam doesn't pop
                clips[i].lockRootRotation = true;      // bake turning into the pose
                clips[i].keepOriginalOrientation = true;
                clips[i].lockRootHeightY = true;       // bake height (bob) into the pose
                clips[i].keepOriginalPositionY = true;
                clips[i].lockRootPositionXZ = false;   // forward drift goes to the root, which the game ignores
                clips[i].keepOriginalPositionXZ = false; // measure that drift from the center of mass
            }
            return clips;
        }

        bool IsCharacterOrAnimation() => assetPath.StartsWith(CharactersDir) || assetPath.StartsWith(AnimationsDir);

        static bool ContainsAny(string text, string[] keywords)
        {
            foreach (var keyword in keywords)
                if (text.Contains(keyword)) return true;
            return false;
        }
    }
}
