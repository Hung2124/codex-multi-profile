// Codex Multi-Profile watcher: tiny background program started at sign-in (HKCU Run).
// Whenever the Microsoft Store Codex is running without the account-menu helper (opened from the taskbar,
// the Start menu, after the helper exited, ...), it starts Start-CodexAccounts.ps1, which reopens Codex
// with the menu if needed and serves it. No window, a few MB, one process list every 1.5 s.
// Built by Install-CodexMultiProfile.ps1 with the C# compiler that ships with .NET Framework.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;

static class CodexAccountsWatcher
{
    const string HostMutex = @"Local\CodexMultiProfileHost";
    const string SelfMutex = @"Local\CodexMultiProfileWatcher";
    static readonly Dictionary<int, bool> isCodex = new Dictionary<int, bool>();

    static bool StoreCodexRunning()
    {
        var alive = new HashSet<int>();
        bool found = false;
        foreach (var p in Process.GetProcessesByName("ChatGPT"))
        {
            using (p)
            {
                alive.Add(p.Id);
                bool codex;
                if (!isCodex.TryGetValue(p.Id, out codex))
                {
                    codex = false;
                    try { codex = p.MainModule.FileName.IndexOf(@"\WindowsApps\OpenAI.Codex_", StringComparison.OrdinalIgnoreCase) >= 0; }
                    catch { }
                    isCodex[p.Id] = codex;
                }
                if (codex) { found = true; }
            }
        }
        foreach (var id in new List<int>(isCodex.Keys)) { if (!alive.Contains(id)) { isCodex.Remove(id); } }
        return found;
    }

    static bool HostRunning()
    {
        Mutex m;
        if (!Mutex.TryOpenExisting(HostMutex, out m)) { return false; }
        m.Dispose();
        return true;
    }

    static void StartHost(string hostScript)
    {
        var psi = new ProcessStartInfo("powershell.exe",
            "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + hostScript + "\"");
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.WorkingDirectory = Path.GetDirectoryName(hostScript);
        using (Process.Start(psi)) { }
    }

    static void Main()
    {
        bool first;
        using (var self = new Mutex(true, SelfMutex, out first))
        {
            if (!first) { return; }
            string root = AppDomain.CurrentDomain.BaseDirectory;
            string hostScript = Path.Combine(root, "Start-CodexAccounts.ps1");
            DateTime lastStart = DateTime.MinValue, hostSeen = DateTime.MinValue;
            int quickExits = 0;
            bool judged = true;
            while (File.Exists(hostScript))
            {
                try
                {
                    DateTime now = DateTime.UtcNow;
                    if (HostRunning())
                    {
                        hostSeen = now;
                        if ((now - lastStart).TotalMinutes > 2) { quickExits = 0; }
                    }
                    else if (StoreCodexRunning())
                    {
                        // A helper that ended within a minute of its start did not manage (port taken, ...):
                        // wait longer each time, up to 10 minutes, instead of retrying every 20 s forever.
                        if (!judged && (hostSeen - lastStart).TotalSeconds < 60) { quickExits++; }
                        judged = true;
                        double wait = Math.Min(600, 20 * Math.Pow(2, Math.Min(quickExits, 5)));
                        if ((now - lastStart).TotalSeconds > wait)
                        {
                            lastStart = now;
                            hostSeen = now;
                            judged = false;
                            StartHost(hostScript);
                        }
                    }
                }
                catch { }
                Thread.Sleep(1500);
            }
        }
    }
}
