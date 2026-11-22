using System.Collections.Generic;
using UnityEngine;
using UnityEngine.UI;

namespace EMPEscape
{
    /// <summary>
    /// The player's phone, shielded from the pulse in their faraday bag. Opened from the HUD once the Ink flag
    /// has_phone is true. Apps: Field-AI, Guide, Comms, Camera, Notes, and the flashlight. One battery
    /// (Ink variable phone_battery, 0-100) feeds them all; the solar panel recharges it from Ink.
    /// World input is locked while the phone is open.
    /// </summary>
    public class PhoneUI : MonoBehaviour
    {
        public static PhoneUI Instance { get; private set; }

        public const string OwnedFlag = "has_phone";
        public const string BatteryVariable = "phone_battery";

        public static readonly Color ScreenColor = new Color(0.05f, 0.06f, 0.08f, 1f);
        public static readonly Color TextColor = new Color(0.9f, 0.93f, 0.95f);
        public static readonly Color DimColor = new Color(0.55f, 0.58f, 0.62f);
        public static readonly Color Accent = new Color(0.39f, 0.82f, 0.78f);
        public static readonly Color AiGreen = new Color(0.66f, 0.9f, 0.63f);

        [Tooltip("Seconds of flashlight per 1% of battery.")]
        public float flashlightSecondsPerPercent = 8f;

        public FieldGuide Guide { get; private set; }
        public readonly List<string> Notes = new List<string>();
        public readonly List<Texture2D> Photos = new List<Texture2D>();
        public bool IsOpen => root != null && root.gameObject.activeSelf;
        /// <summary>Full-screen layer outside the phone's frame (the camera viewfinder lives here).</summary>
        public RectTransform OverlayRoot => root;
        /// <summary>Set by an app that must finish first (e.g. a chat waiting for your reply).</summary>
        public bool NavigationLocked { get; set; }

        RectTransform root;
        Image shade;
        RectTransform frame;
        RectTransform home;
        RectTransform appArea;
        Text appTitle;
        Text status;
        Text batteryLabel;
        RectTransform deadScreen;
        Text notesTile;
        Text lightTile;
        Image lightTileImage;

        readonly List<PhoneApp> apps = new List<PhoneApp>();
        PhoneApp current;
        int unreadNotes;
        float drain;
        float nextRefresh;

        public void Build(RectTransform parent)
        {
            Instance = this;
            Guide = FieldGuide.Load();

            shade = UIFactory.Panel("Phone", parent, new Color(0f, 0f, 0f, 0.55f));
            root = shade.rectTransform.Stretch();

            var body = UIFactory.Panel("Frame", root, new Color(0.11f, 0.12f, 0.13f, 1f));
            frame = body.rectTransform.Anchor(new Vector2(0.5f, 0.03f), new Vector2(0.5f, 0.97f), new Vector2(-290f, 0f), new Vector2(290f, 0f));
            var screen = UIFactory.Panel("Screen", frame, ScreenColor).rectTransform.Stretch(new Vector2(16f, 16f));

            status = UIFactory.Label("Status", screen, 24, TextAnchor.MiddleLeft, DimColor);
            status.rectTransform.Anchor(new Vector2(0f, 1f), new Vector2(1f, 1f), new Vector2(20f, -44f), new Vector2(-120f, -6f));
            batteryLabel = UIFactory.Label("Battery", screen, 24, TextAnchor.MiddleRight, TextColor);
            batteryLabel.rectTransform.Anchor(new Vector2(1f, 1f), new Vector2(1f, 1f), new Vector2(-140f, -44f), new Vector2(-20f, -6f));

            var content = UIFactory.NewRect("Content", screen).Anchor(Vector2.zero, Vector2.one, new Vector2(0f, 84f), new Vector2(0f, -48f));
            appTitle = UIFactory.Label("AppTitle", content, 34, TextAnchor.MiddleLeft, TextColor);
            appTitle.fontStyle = FontStyle.Bold;
            appTitle.rectTransform.Anchor(new Vector2(0f, 1f), new Vector2(1f, 1f), new Vector2(20f, -56f), new Vector2(-20f, 0f));
            appArea = UIFactory.NewRect("Apps", content).Anchor(Vector2.zero, Vector2.one, new Vector2(10f, 0f), new Vector2(-10f, -60f));

            home = UIFactory.NewRect("Home", content).Stretch();
            BuildHome();

            Register(new FieldAIApp());
            Register(new GuideApp());
            Register(new CommsApp());
            Register(new CameraApp());
            Register(new NotesApp());

            deadScreen = UIFactory.Panel("Dead", content, ScreenColor).rectTransform.Stretch();
            var dead = UIFactory.Label("Message", deadScreen, 34, TextAnchor.MiddleCenter, DimColor);
            dead.text = "BATTERY EMPTY\n\n<size=26>Charge the phone with the solar panel.</size>";
            dead.rectTransform.Stretch(new Vector2(30f, 0f));

            var bar = UIFactory.NewRect("NavBar", screen).Anchor(Vector2.zero, new Vector2(1f, 0f), new Vector2(12f, 10f), new Vector2(-12f, 74f));
            var layout = bar.gameObject.AddComponent<HorizontalLayoutGroup>();
            layout.spacing = 10f;
            layout.childControlWidth = layout.childControlHeight = true;
            layout.childForceExpandWidth = layout.childForceExpandHeight = true;
            NavButton(bar, "BACK", GoBack);
            NavButton(bar, "HOME", () => { if (!NavigationLocked) ShowHome(); });
            NavButton(bar, "CLOSE", Close);

            root.gameObject.SetActive(false);
        }

        void BuildHome()
        {
            var grid = UIFactory.NewRect("Grid", home).Anchor(Vector2.zero, Vector2.one, new Vector2(10f, 0f), new Vector2(-10f, -70f));
            var layout = grid.gameObject.AddComponent<GridLayoutGroup>();
            layout.cellSize = new Vector2(150f, 150f);
            layout.spacing = new Vector2(18f, 22f);
            layout.constraint = GridLayoutGroup.Constraint.FixedColumnCount;
            layout.constraintCount = 3;
            layout.childAlignment = TextAnchor.UpperCenter;

            var hint = UIFactory.Label("Hint", home, 24, TextAnchor.MiddleCenter, DimColor);
            hint.text = "Offline. Shielded in the faraday bag when the pulse hit.";
            hint.rectTransform.Anchor(new Vector2(0f, 1f), new Vector2(1f, 1f), new Vector2(10f, -60f), new Vector2(-10f, 0f));

            Tile(grid, "AI", "FIELD-AI", new Color(0.16f, 0.32f, 0.2f), () => OpenApp("Field-AI"));
            Tile(grid, "?", "GUIDE", new Color(0.18f, 0.25f, 0.36f), () => OpenApp("Guide"));
            Tile(grid, "((·))", "COMMS", new Color(0.13f, 0.3f, 0.33f), () => OpenApp("Comms"));
            Tile(grid, "[o]", "CAMERA", new Color(0.25f, 0.25f, 0.28f), () => OpenApp("Camera"));
            notesTile = Tile(grid, "=", "NOTES", new Color(0.36f, 0.3f, 0.16f), () => OpenApp("Notes"));
            lightTile = Tile(grid, "*", "LIGHT", new Color(0.22f, 0.22f, 0.22f), ToggleFlashlight);
            lightTileImage = lightTile.transform.parent.GetComponent<Image>();
        }

        Text Tile(RectTransform grid, string glyph, string name, Color color, UnityEngine.Events.UnityAction action)
        {
            var button = UIFactory.MakeButton(name, grid, 30, out var label);
            button.GetComponent<Image>().color = color;
            label.text = $"<size=48><b>{glyph}</b></size>\n{name}";
            label.rectTransform.Stretch(new Vector2(4f, 4f));
            button.onClick.AddListener(action);
            return label;
        }

        static void NavButton(RectTransform bar, string name, UnityEngine.Events.UnityAction action)
        {
            var button = UIFactory.MakeButton(name, bar, 26, out var label);
            label.text = name;
            button.onClick.AddListener(action);
        }

        void Register(PhoneApp app)
        {
            app.Build(this, appArea);
            apps.Add(app);
        }

        // ---------- open / close / navigate ----------

        public void Open()
        {
            if (IsOpen) return;
            GameInput.Lock();
            root.gameObject.SetActive(true);
            SetFrameVisible(true);
            AudioDirector.Play("ui_open", 0.7f);
            ShowHome();
        }

        public void Close()
        {
            if (!IsOpen || NavigationLocked) return;
            if (current != null) current.Hide();
            current = null;
            root.gameObject.SetActive(false);
            GameInput.Unlock();
            AudioDirector.Play("ui_close", 0.6f);
        }

        public void ShowHome()
        {
            if (current != null) current.Hide();
            current = null;
            home.gameObject.SetActive(true);
            appTitle.text = "";
            Refresh();
        }

        public void OpenApp(string title)
        {
            if (IsDead) return;
            var app = apps.Find(a => a.Title == title);
            if (app == null) return;
            home.gameObject.SetActive(false);
            if (current != null) current.Hide();
            current = app;
            appTitle.text = title.ToUpperInvariant();
            app.Show();
        }

        void GoBack()
        {
            if (NavigationLocked) return;
            if (current == null) Close();
            else if (!current.Back()) ShowHome();
        }

        /// <summary>The camera viewfinder hides the phone so the world shows full screen.</summary>
        public void SetFrameVisible(bool visible)
        {
            frame.gameObject.SetActive(visible);
            shade.color = new Color(0f, 0f, 0f, visible ? 0.55f : 0f);
        }

        // ---------- battery ----------

        public int Battery
        {
            get
            {
                var story = StoryDirector.Instance;
                return story != null && story.HasVariable(BatteryVariable) ? story.GetInt(BatteryVariable) : 100;
            }
            set
            {
                if (StoryDirector.Instance != null) StoryDirector.Instance.SetInt(BatteryVariable, Mathf.Clamp(value, 0, 100));
                Refresh();
            }
        }

        public bool IsDead => Battery <= 0;

        /// <summary>Spends battery. False (and nothing spent) if there isn't enough.</summary>
        public bool UseBattery(int percent)
        {
            if (Battery < percent) return false;
            Battery -= percent;
            return true;
        }

        // ---------- notes and flashlight ----------

        public void AddNote(string text)
        {
            Notes.Add(text);
            unreadNotes++;
            AudioDirector.Play("msg_in", 0.5f);
            Refresh();
        }

        public void MarkNotesRead()
        {
            unreadNotes = 0;
            Refresh();
        }

        public void ToggleFlashlight()
        {
            var light = Flashlight.Player;
            if (light == null) return;
            if (!light.IsOn && IsDead) return;
            light.Toggle();
            Refresh();
        }

        void Update()
        {
            var light = Flashlight.Player;
            if (light != null && light.IsOn)
            {
                drain += Time.deltaTime;
                if (drain >= flashlightSecondsPerPercent)
                {
                    drain = 0f;
                    if (!UseBattery(1) || IsDead) light.Set(false);
                }
            }
            if (IsOpen && Time.unscaledTime >= nextRefresh) Refresh();
        }

        void Refresh()
        {
            nextRefresh = Time.unscaledTime + 0.5f;
            if (batteryLabel == null) return;
            int battery = Battery;
            batteryLabel.text = battery + "%";
            batteryLabel.color = battery <= 15 ? new Color(1f, 0.45f, 0.4f) : TextColor;
            status.text = CommsApp.ConnectedNetwork() is string network ? "WI-FI: " + network : "NO SERVICE";
            notesTile.text = $"<size=48><b>=</b></size>\n{(unreadNotes > 0 ? $"NOTES ({unreadNotes})" : "NOTES")}";
            bool lit = Flashlight.Player != null && Flashlight.Player.IsOn;
            lightTile.text = $"<size=48><b>*</b></size>\nLIGHT {(lit ? "ON" : "OFF")}";
            lightTileImage.color = lit ? new Color(0.62f, 0.55f, 0.2f) : new Color(0.22f, 0.22f, 0.22f);
            deadScreen.gameObject.SetActive(battery <= 0);
        }
    }
}
