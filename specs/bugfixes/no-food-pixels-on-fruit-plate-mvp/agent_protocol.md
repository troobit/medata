# Agent Protocol — STOP-task convention

Tasks prefixed with **STOP —** in `tasks.md` are human-in-loop device-verification phases. The Claude agent driving this spec CANNOT build for the iPhone, install via `devicectl`, or read live Console logs without the user. When a STOP task is reached, the agent MUST:

1. Build the App scheme for the device destination (`xcodebuild ... -destination 'id=76A45E6D-…'`) and confirm `** BUILD SUCCEEDED **`.
2. Print the `xcrun devicectl device install app --device 76A45E6D-…` and `xcrun devicectl device process launch ... rtob.MeData` commands the user runs.
3. Print the Console.app filter the user sets (`subsystem:ie.medata.app category:Shutter`, with Action → Include Info Messages + Include Debug Messages enabled).
4. List the exact taps the user performs (mode, stage count, scene).
5. Wait for the user to paste the trail back. **Do not iterate code while waiting.** **Do not fabricate a trail.**

When the user pastes a trail, the agent diagnoses from it and proceeds to the next task.
