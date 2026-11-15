using System;
using UnityEngine;
using UnityEngine.AI;

namespace EMPEscape
{
    /// <summary>
    /// Player movement. Drag anywhere for a floating virtual stick (walk in any direction, including back
    /// toward the camera). A quick tap on the ground walks there; a tap on a hotspot opens its verb menu.
    /// The stick keeps the camera direction it started with until you let go, so camera cuts don't flip it.
    /// </summary>
    [RequireComponent(typeof(NavMeshAgent))]
    public class PlayerController : MonoBehaviour
    {
        public static PlayerController Instance { get; private set; }

        public LayerMask tapMask = ~0;
        public float arriveTolerance = 0.2f;

        [Header("Virtual stick")]
        [Tooltip("How far (fraction of screen height) a press must move before it becomes a stick drag.")]
        public float dragThreshold = 0.025f;
        [Tooltip("Stick radius as a fraction of screen height. Must match JoystickUI's ring.")]
        public float stickRadius = 0.1f;
        [Tooltip("Stick deflection below this is ignored.")]
        public float deadZone = 0.15f;
        [Tooltip("Slowest walk speed as a fraction of the agent's speed, at a light push.")]
        public float minSpeedFraction = 0.4f;
        public float turnSpeed = 720f;

        NavMeshAgent agent;
        Camera cam;
        HotspotMenu hotspotMenu;
        JoystickUI joystick;
        Action onArrive;
        bool moving;

        bool tracking;
        bool dragging;
        Vector2 pressStart;
        Vector3 stickForward;
        Vector3 stickRight;

        void Awake()
        {
            Instance = this;
            agent = GetComponent<NavMeshAgent>();
        }

        void Start()
        {
            cam = Camera.main;
            hotspotMenu = GameUI.Instance.HotspotMenu;
            joystick = GameUI.Instance.Joystick;
            if (!agent.isOnNavMesh) agent.Warp(transform.position);
        }

        void Update()
        {
            CheckArrival();
            HandlePointer();
        }

        void HandlePointer()
        {
            if (GameInput.WorldLocked)
            {
                if (tracking) EndPress();
                return;
            }

            if (GameInput.PressedThisFrame(out var down) && !GameInput.IsOverUI(down))
            {
                tracking = true;
                dragging = false;
                pressStart = down;
            }
            if (!tracking) return;

            if (GameInput.IsPressed(out var position))
            {
                var offset = position - pressStart;
                float screen = Screen.height;
                if (!dragging && offset.magnitude > dragThreshold * screen) BeginDrag();
                if (dragging) Steer(position, offset, screen);
                return;
            }

            // Released: a press that never became a drag is a tap.
            if (!dragging) HandleTap(pressStart);
            EndPress();
        }

        void BeginDrag()
        {
            dragging = true;
            hotspotMenu.Hide();
            Stop();

            var forward = cam.transform.forward;
            forward.y = 0f;
            if (forward.sqrMagnitude < 0.001f) { forward = cam.transform.up; forward.y = 0f; }
            forward.Normalize();
            stickForward = forward;
            stickRight = new Vector3(forward.z, 0f, -forward.x);

            joystick.Show(pressStart);
        }

        void Steer(Vector2 position, Vector2 offset, float screen)
        {
            float radius = stickRadius * screen;

            // Floating stick: if the thumb runs past the ring, drag the ring along with it.
            if (offset.magnitude > radius)
            {
                pressStart = position - offset.normalized * radius;
                offset = position - pressStart;
                joystick.MoveBase(pressStart);
            }

            var stick = Vector2.ClampMagnitude(offset / radius, 1f);
            joystick.SetKnob(stick);

            float amount = stick.magnitude;
            if (amount < deadZone) return;

            var direction = (stickRight * stick.x + stickForward * stick.y).normalized;
            float speed = agent.speed * Mathf.Lerp(minSpeedFraction, 1f, Mathf.InverseLerp(deadZone, 0.9f, amount));
            agent.Move(direction * speed * Time.deltaTime);
            transform.rotation = Quaternion.RotateTowards(transform.rotation, Quaternion.LookRotation(direction), turnSpeed * Time.deltaTime);
        }

        void EndPress()
        {
            tracking = false;
            if (!dragging) return;
            dragging = false;
            joystick.Hide();
        }

        void HandleTap(Vector2 screenPos)
        {
            var ray = cam.ScreenPointToRay(screenPos);
            if (!Physics.Raycast(ray, out var hit, 200f, tapMask, QueryTriggerInteraction.Ignore))
            {
                hotspotMenu.Hide();
                return;
            }

            var hotspot = hit.collider.GetComponentInParent<Hotspot>();
            if (hotspot != null)
            {
                hotspotMenu.Show(hotspot);
                return;
            }

            hotspotMenu.Hide();
            if (NavMesh.SamplePosition(hit.point, out var navHit, 1.5f, NavMesh.AllAreas))
                MoveTo(navHit.position, null);
        }

        void CheckArrival()
        {
            if (!moving || agent.pathPending) return;
            if (agent.remainingDistance > agent.stoppingDistance + arriveTolerance) return;

            moving = false;
            var callback = onArrive;
            onArrive = null;
            callback?.Invoke();
        }

        public void MoveTo(Vector3 target, Action arrived)
        {
            onArrive = arrived;
            moving = true;
            agent.isStopped = false;
            agent.SetDestination(target);
        }

        public void Stop()
        {
            if (agent.isOnNavMesh) agent.ResetPath();
            moving = false;
            onArrive = null;
        }

        public void FaceTowards(Vector3 point)
        {
            var direction = point - transform.position;
            direction.y = 0f;
            if (direction.sqrMagnitude > 0.001f) transform.rotation = Quaternion.LookRotation(direction);
        }
    }
}
