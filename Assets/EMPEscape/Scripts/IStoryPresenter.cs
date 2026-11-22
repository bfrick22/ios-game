using System;
using System.Collections;
using System.Collections.Generic;
using Ink.Runtime;

namespace EMPEscape
{
    /// <summary>
    /// Where a knot's lines and choices are shown. DialogueUI (subtitles) is the default; the phone's
    /// Comms app shows them as chat messages. Pass one to StoryDirector.RunKnot(knot, presenter).
    /// </summary>
    public interface IStoryPresenter
    {
        IEnumerator ShowLine(string speaker, string line);
        IEnumerator ShowChoices(List<Choice> choices, float timerSeconds, Action<int> onPicked);
        void HideLine();
    }
}
