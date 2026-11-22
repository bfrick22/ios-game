using UnityEngine;

namespace EMPEscape
{
    /// <summary>One app on the phone. PhoneUI builds each into the app area and shows one at a time.</summary>
    public abstract class PhoneApp
    {
        protected PhoneUI Phone { get; private set; }
        protected RectTransform Page { get; private set; }

        public abstract string Title { get; }

        public void Build(PhoneUI phone, RectTransform area)
        {
            Phone = phone;
            Page = UIFactory.NewRect(Title, area).Stretch();
            Create();
            Page.gameObject.SetActive(false);
        }

        protected abstract void Create();

        public virtual void Show() => Page.gameObject.SetActive(true);
        public virtual void Hide() => Page.gameObject.SetActive(false);

        /// <summary>Back button inside the app. Return true if the app handled it (e.g. left a sub-page).</summary>
        public virtual bool Back() => false;
    }
}
