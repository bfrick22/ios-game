using System.IO;
using UnityEditor;

namespace EMPEscape.EditorTools
{
    /// <summary>
    /// Import defaults for EMP Escape art, applied the first time a file is imported (your later
    /// Inspector changes stick):
    ///   Art/Characters/*  -> Humanoid rig, avatar from the model
    ///   Art/Animations/*  -> Humanoid rig; a single clip is named after its file; clips with idle/walk/talk/run in the name loop
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
            var fileName = Path.GetFileNameWithoutExtension(assetPath);
            var clips = importer.defaultClipAnimations;
            for (int i = 0; i < clips.Length; i++)
            {
                // One clip per file (Mixamo): name it after the file. Many clips per file (animation libraries): keep their names.
                if (clips.Length == 1) clips[i].name = fileName;
                clips[i].loopTime = ContainsAny(clips[i].name.ToLowerInvariant(), LoopingKeywords);
                clips[i].lockRootRotation = true;
                clips[i].lockRootHeightY = true;
                clips[i].lockRootPositionXZ = true;
                clips[i].keepOriginalOrientation = true;
                clips[i].keepOriginalPositionY = true;
                clips[i].keepOriginalPositionXZ = true;
            }
            importer.clipAnimations = clips;
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
