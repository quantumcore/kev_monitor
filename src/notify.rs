/// Send a desktop toast notification.
///
/// * **Windows** — uses PowerShell's BurntToast / Windows.UI.Notifications
///   via a one-liner that works on Windows 10/11 without extra crates.
/// * **Linux**   — uses `notify-send` (libnotify), present on most distros.
///
/// Failures are logged but never propagate (non-critical path).
pub fn send(title: &str, body: &str) {
    #[cfg(target_os = "windows")]
    windows_toast(title, body);

    #[cfg(target_os = "linux")]
    linux_notify(title, body);

    #[cfg(target_os = "macos")]
    macos_notify(title, body);

    #[cfg(not(any(target_os = "windows", target_os = "linux", target_os = "macos")))]
    eprintln!("[notify] Platform not supported for toast notifications.");
}

// ── Windows ──────────────────────────────────────────────────────────────────

#[cfg(target_os = "windows")]
fn windows_toast(title: &str, body: &str) {
    // Escape single-quotes for PowerShell string literals
    let t = title.replace('\'', "''");
    let b = body.replace('\'', "''");

    let script = format!(
        r#"
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null
$template = [Windows.UI.Notifications.ToastTemplateType]::ToastText02
$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent($template)
$xml.GetElementsByTagName('text')[0].AppendChild($xml.CreateTextNode('{t}')) | Out-Null
$xml.GetElementsByTagName('text')[1].AppendChild($xml.CreateTextNode('{b}')) | Out-Null
$toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('KEV Monitor').Show($toast)
"#,
        t = t,
        b = b
    );

    let result = std::process::Command::new("powershell")
        .args(["-NoProfile", "-NonInteractive", "-Command", &script])
        .output();

    match result {
        Ok(o) if o.status.success() => {}
        Ok(o) => eprintln!(
            "[notify] PowerShell toast failed: {}",
            String::from_utf8_lossy(&o.stderr)
        ),
        Err(e) => eprintln!("[notify] Failed to launch PowerShell: {e}"),
    }
}

// ── Linux ─────────────────────────────────────────────────────────────────────

#[cfg(target_os = "linux")]
fn linux_notify(title: &str, body: &str) {
    let result = std::process::Command::new("notify-send")
        .args([
            "--icon=dialog-information",
            "--urgency=normal",
            title,
            body,
        ])
        .output();

    match result {
        Ok(o) if o.status.success() => {}
        Ok(o) => eprintln!(
            "[notify] notify-send failed: {}",
            String::from_utf8_lossy(&o.stderr)
        ),
        Err(e) => eprintln!("[notify] Failed to launch notify-send: {e}  (is libnotify-bin installed?)"),
    }
}
