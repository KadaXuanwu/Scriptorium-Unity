using System.IO;
using UnityEditor;

namespace Scriptorium.Editor {
    // A Scriptorium worker writes Temp/ScriptoriumRunEnded when its run ends for any reason. The editor then leaves play
    // mode, so an editor that a run left playing does not use power while the worker waits.
    [InitializeOnLoad]
#if UNITY_6000_7_OR_NEWER
    [Unity.Scripting.LifecycleManagement.NoAutoStaticsCleanup]
#endif
    internal static class RunEnd {
        private const string MarkerPath = "Temp/ScriptoriumRunEnded";
        private const double PollSeconds = 2.0;
        private static double nextPoll;

        static RunEnd() {
            EditorApplication.update += Poll;
        }

        private static void Poll() {
            if (EditorApplication.timeSinceStartup < nextPoll) {
                return;
            }
            nextPoll = EditorApplication.timeSinceStartup + PollSeconds;
            if (!File.Exists(MarkerPath)) {
                return;
            }
            File.Delete(MarkerPath);
            if (EditorApplication.isPlaying) {
                EditorApplication.ExitPlaymode();
            }
        }
    }
}
