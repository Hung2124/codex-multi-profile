# Optional desktop layer (clone only)

Off by default. Inspired by LightHaru/chatgpt-layer / Codex++ look and feel
(badge, wider transcript, keep details open) -- not their asar patcher.

## Enable

```powershell
$m = "$env:LOCALAPPDATA\CodexParallelDesktop\CodexProfile.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action layer
powershell -NoProfile -ExecutionPolicy Bypass -File $m -Action layer -Disable
```

When off, launch is unchanged: the cmd wrapper does set + start of the cloned ChatGPT.exe.
When on, the same wrapper adds a loopback remote-debugging port on the clone only,
and Start-CodexLayer.ps1 applies scripts/layer-inject.js.

## Hard rules

- Never the Microsoft Store package / WindowsApps
- Never unpack or rewrite asar or ChatGPT.exe
- Loopback 127.0.0.1 only
- Refuses the Store binary
