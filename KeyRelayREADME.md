# KeyRelay

**KeyRelay** is a PowerShell GUI tool that sends text to applications **by simulating keystrokes** instead of using the clipboard.

This is useful for environments where **paste is disabled or blocked**, such as:

* Restricted consoles
* Remote shells
* Legacy applications
* Secure terminals
* iDRAC / BMC consoles
* Training lab environments
* Cluster management consoles

KeyRelay allows you to **type commands automatically into another application window**.

---

# Features

### Keystroke Relay

Instead of pasting text, KeyRelay types characters one-by-one using Windows SendKeys.

### Command Library

Store commonly used commands in categorized lists.

### Command History

Automatically remembers recently executed commands.

### Adjustable Typing Speed

Configure delays to ensure compatibility with slow terminals.

### Multi-Line Script Support

Send entire scripts line-by-line.

### Cluster Execution Mode

Automatically wrap commands in:

```
Invoke-Command -ComputerName (Get-ClusterNode).Name -ScriptBlock { }
```

### Window Switching

Optional automatic **Alt+Tab** to the previous window before typing begins.

### Always-On-Top Mode

Keep the KeyRelay window visible while working.

### Persistent Settings

User settings automatically saved between sessions.

---

# Running KeyRelay

Launch the GUI by copying and pasting the following into PowerShell or Terminal:

```powershell
Echo KeyRelay;[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="KeyRelay";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('http'+'s://raw.githubusercontent.com/DellProSupportGse/Tools/main/KeyRelay.ps1'));Invoke-KeyRelay
```
NOTE: No admin rights needed when opening PowerShell or Terminal

---
# KeyRelay Quick Start

Step 1 — Launch KeyRelay

Run:

Invoke-KeyRelay

Step 2 — Enter Your Command

Paste or type the command into the main editor.

Example:

Get-ClusterNode

Step 3 — Set Start Delay

Set a delay (3–5 seconds recommended).

This gives you time to switch to the target window.

Step 4 — Click "Type It"

KeyRelay will wait the configured delay.

Step 5 — Switch to the Target Application

Select the console or application that should receive the command.

Step 6 — Watch the Command Type Automatically

KeyRelay will simulate typing the command.

Optional Features

Run on Cluster Nodes
Automatically runs the command on all cluster nodes.

Select Previous Window on Type
Automatically switches to the previous window.

Press Enter After Each Line
Useful for multi-line scripts.

Tip

If typing appears too fast for the destination console, increase the **Per-Key Delay** setting.

---

# File Locations

KeyRelay stores data in the user's Documents folder.

```
Documents\KeyRelay\
```

Files created:

| File                   | Purpose          |
| ---------------------- | ---------------- |
| KeyRelay.commands.json | Command library  |
| KeyRelay.history.json  | Command history  |
| KeyRelay.settings.json | User preferences |

---

# Main Interface

KeyRelay has four primary areas:

### Command Editor

Where you enter the command or script you want to relay.

### Commands Tab

A categorized command library.

Double-click a command to load it into the editor.

### History Tab

Shows recently executed commands.

### Control Panel

Typing speed and behavior controls.

---

# Settings

| Setting                        | Description                         |
| ------------------------------ | ----------------------------------- |
| Start Delay                    | Delay before typing begins          |
| Per-Key Delay                  | Delay between characters            |
| Between Lines                  | Delay between lines                 |
| Press Enter After Each Line    | Sends Enter after every line        |
| Run on Cluster Nodes           | Wrap command in Invoke-Command      |
| Select Previous Window on Type | Automatically Alt-Tab before typing |

---

# Typical Workflow

1. Open KeyRelay
2. Paste or type your command into the editor
3. Configure delays if needed
4. Click **Type It**
5. Switch to the target window
6. KeyRelay types the command automatically

---

# Example

Command entered in KeyRelay:

```
Get-ClusterNode
```

KeyRelay types it into the target console exactly as if you typed it manually.

---

# Best Practices

### Use a Start Delay

Recommended:

```
3–5 seconds
```

This gives time to switch to the destination window.

---

### Adjust Delays for Slow Consoles

Example:

```
Per-Key Delay: 50ms
Line Delay: 200ms
```

---

### Save Frequently Used Commands

Use the **Command Library** to store common scripts.

---

# Safety Notes

KeyRelay sends keystrokes directly to the active application.

Always ensure the **correct window is focused before typing begins**.

---

# Author

Jim Gandy
