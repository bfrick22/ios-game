using System.Collections;
using UnityEngine;
using UnityEngine.UI;

namespace EMPEscape
{
    /// <summary>
    /// Camera: the phone steps aside for a full-screen viewfinder over the game view. The shutter takes a real
    /// screenshot (2% battery) into the Photos list. If a PhotoSubject is in the shot and close enough, the
    /// phone closes and its Ink knot runs, e.g. photographing a manual loads its data pack.
    /// Photos last for the session.
    /// </summary>
    public class CameraApp : PhoneApp
    {
        const int CostPerPhoto = 2;
        const int MaxPhotos = 30;
        const int PhotoWidth = 960;

        public override string Title => "Camera";

        RectTransform viewfinder;
        Text info;
        Image flash;
        ScrollRect galleryScroll;
        RectTransform gallery;
        bool capturing;

        protected override void Create()
        {
            // Gallery lives in the phone's frame.
            galleryScroll = UIFactory.ScrollList("Photos", Page, 12f, out gallery);
            ((RectTransform)galleryScroll.transform).Stretch();

            // Viewfinder lives full screen, outside the frame.
            viewfinder = UIFactory.NewRect("Viewfinder", Phone.OverlayRoot).Stretch();
            var bracketColor = new Color(1f, 1f, 1f, 0.85f);
            foreach (var corner in new[] { new Vector2(0f, 0f), new Vector2(1f, 0f), new Vector2(0f, 1f), new Vector2(1f, 1f) })
                Bracket(viewfinder, corner, bracketColor);
            var center = UIFactory.Panel("Center", viewfinder, new Color(1f, 1f, 1f, 0.6f));
            center.sprite = UIFactory.RingSprite;
            center.raycastTarget = false;
            center.rectTransform.Center(new Vector2(90f, 90f));

            info = UIFactory.Label("Info", viewfinder, 30, TextAnchor.UpperCenter, Color.white);
            info.rectTransform.Anchor(new Vector2(0.2f, 1f), new Vector2(0.8f, 1f), new Vector2(0f, -90f), new Vector2(0f, -30f));

            var shutter = UIFactory.Panel("Shutter", viewfinder, Color.white);
            shutter.sprite = UIFactory.CircleSprite;
            shutter.rectTransform.Anchor(new Vector2(1f, 0.5f), new Vector2(1f, 0.5f), new Vector2(-210f, -75f), new Vector2(-60f, 75f));
            var shutterButton = shutter.gameObject.AddComponent<Button>();
            shutterButton.onClick.AddListener(() => Phone.StartCoroutine(Capture()));

            var back = UIFactory.MakeButton("Back", viewfinder, 30, out var backLabel);
            backLabel.text = "BACK";
            back.GetComponent<RectTransform>().Anchor(Vector2.zero, Vector2.zero, new Vector2(40f, 40f), new Vector2(240f, 110f));
            back.onClick.AddListener(() => Phone.ShowHome());

            var photos = UIFactory.MakeButton("Photos", viewfinder, 30, out var photosLabel);
            photosLabel.text = "PHOTOS";
            photos.GetComponent<RectTransform>().Anchor(new Vector2(1f, 0f), new Vector2(1f, 0f), new Vector2(-260f, 40f), new Vector2(-40f, 110f));
            photos.onClick.AddListener(ShowGallery);

            flash = UIFactory.Panel("Flash", viewfinder, new Color(1f, 1f, 1f, 0f));
            flash.rectTransform.Stretch();
            flash.raycastTarget = false;

            viewfinder.gameObject.SetActive(false);
        }

        static void Bracket(RectTransform parent, Vector2 corner, Color color)
        {
            var inset = new Vector2(corner.x == 0f ? 80f : -80f, corner.y == 0f ? 80f : -80f);
            var horizontal = UIFactory.Panel("Bracket", parent, color);
            horizontal.raycastTarget = false;
            var h = horizontal.rectTransform;
            h.anchorMin = h.anchorMax = corner;
            h.pivot = corner;
            h.sizeDelta = new Vector2(90f, 6f);
            h.anchoredPosition = inset;
            var vertical = UIFactory.Panel("Bracket", parent, color);
            vertical.raycastTarget = false;
            var v = vertical.rectTransform;
            v.anchorMin = v.anchorMax = corner;
            v.pivot = corner;
            v.sizeDelta = new Vector2(6f, 90f);
            v.anchoredPosition = inset;
        }

        public override void Show()
        {
            base.Show();
            ShowViewfinder();
        }

        public override void Hide()
        {
            viewfinder.gameObject.SetActive(false);
            Phone.SetFrameVisible(true);
            base.Hide();
        }

        public override bool Back()
        {
            ShowViewfinder(); // from the photo list back to the viewfinder
            return true;
        }

        void ShowViewfinder()
        {
            galleryScroll.gameObject.SetActive(false);
            viewfinder.gameObject.SetActive(true);
            Phone.SetFrameVisible(false);
            UpdateInfo();
        }

        void ShowGallery()
        {
            viewfinder.gameObject.SetActive(false);
            Phone.SetFrameVisible(true);
            galleryScroll.gameObject.SetActive(true);
            for (int i = gallery.childCount - 1; i >= 0; i--) Object.Destroy(gallery.GetChild(i).gameObject);
            if (Phone.Photos.Count == 0)
                UIFactory.Paragraph("Empty", gallery, 26, PhoneUI.DimColor, "No photos yet.");
            for (int i = Phone.Photos.Count - 1; i >= 0; i--)
            {
                var photo = Phone.Photos[i];
                var image = UIFactory.NewRect("Photo", gallery).gameObject.AddComponent<RawImage>();
                image.texture = photo;
                image.gameObject.AddComponent<LayoutElement>().preferredHeight = 500f * photo.height / Mathf.Max(1, photo.width);
            }
            galleryScroll.verticalNormalizedPosition = 1f;
        }

        void UpdateInfo() => info.text = $"{Phone.Photos.Count} PHOTOS     {Phone.Battery}%";

        IEnumerator Capture()
        {
            if (capturing) yield break;
            if (!Phone.UseBattery(CostPerPhoto))
            {
                info.text = "BATTERY TOO LOW";
                AudioDirector.Play("device_error", 0.6f);
                yield break;
            }
            capturing = true;

            // Hide all UI for one frame so the photo is just the world.
            var canvas = Phone.OverlayRoot.GetComponentInParent<Canvas>();
            canvas.enabled = false;
            yield return new WaitForEndOfFrame();
            var shot = ScreenCapture.CaptureScreenshotAsTexture();
            canvas.enabled = true;

            Phone.Photos.Add(Downscale(shot, PhotoWidth));
            while (Phone.Photos.Count > MaxPhotos)
            {
                Object.Destroy(Phone.Photos[0]);
                Phone.Photos.RemoveAt(0);
            }
            AudioDirector.Play("camera_shutter", 0.9f);
            UpdateInfo();
            for (float t = 0f; t < 0.2f; t += Time.unscaledDeltaTime)
            {
                flash.color = new Color(1f, 1f, 1f, 0.8f * (1f - t / 0.2f));
                yield return null;
            }
            flash.color = new Color(1f, 1f, 1f, 0f);
            capturing = false;

            var player = PlayerController.Instance;
            var subject = player != null ? PhotoSubject.InShot(Camera.main, player.transform.position) : null;
            if (subject == null) yield break;
            yield return new WaitForSeconds(0.3f);
            bool lit = Flashlight.Player != null && Flashlight.Player.IsOn;
            Phone.Close();
            if (StoryDirector.Instance != null) StoryDirector.Instance.RunKnot(subject.KnotFor(lit));
        }

        static Texture2D Downscale(Texture2D source, int width)
        {
            width = Mathf.Min(width, source.width);
            int height = Mathf.RoundToInt(source.height * (width / (float)source.width));
            var temporary = RenderTexture.GetTemporary(width, height);
            Graphics.Blit(source, temporary);
            var previous = RenderTexture.active;
            RenderTexture.active = temporary;
            var result = new Texture2D(width, height, TextureFormat.RGB24, false);
            result.ReadPixels(new Rect(0, 0, width, height), 0, 0);
            result.Apply();
            RenderTexture.active = previous;
            RenderTexture.ReleaseTemporary(temporary);
            Object.Destroy(source);
            return result;
        }
    }
}
