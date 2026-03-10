
# KeyRelay

**Version:** KeyRelay v1.13

KeyRelay is a PowerShell GUI tool designed to send commands or text into applications that do not support paste operations.

This tool is especially useful when working with:

- iDRAC virtual consoles
- KVM consoles
- Serial sessions
- Restricted remote shells
- Secure administrative terminals

KeyRelay safely types commands using a configurable typing engine.

---

# Features

- Command relay typing engine
- Configurable typing delays
- Command libraries organized by category
- Shared commands loaded from GitHub
- Command history tracking
- Search across commands and history
- Add, edit, and remove commands from the GUI
- Copy commands directly from the command tree
- Cluster execution support
- Keyboard layout targeting
- JSON-based configuration storage
- Always-on-top window option

---

# Command Libraries

KeyRelay supports multiple command sources.

## My Commands

Your personal command library stored locally.

Location:

Documents\KeyRelay\KeyRelay.commands.json

Categories help organize commands.

---

## Shared Commands

Commands can be downloaded dynamically from GitHub.

Repository:

https://github.com/DellProSupportGse/Tools

Shared commands include examples for:

- Windows Server management
- Azure Local troubleshooting
- Failover cluster diagnostics
- Hyper-V administration
- Network ATC configuration

Descriptions are displayed using tooltips.

---

# Search

The search bar filters commands in real time.

Search works across:

- My Commands
- Shared Commands
- History

Results update automatically while typing.

---

# Command Editor

Commands can be managed directly from the interface.

Right-click a command in **My Commands** to access:

- Copy Command
- Edit Command
- Remove Command
- Remove Category

---

# Typing Engine

KeyRelay uses the Windows SendKeys API to simulate typing.

Configurable options include:

| Setting | Description |
|---|---|
| Start Delay | Time before typing begins |
| Per-Key Delay | Delay between characters |
| Line Delay | Delay between command lines |

Typing can be cancelled using the **STOP** button.

---

# Cluster Mode

When enabled, KeyRelay executes commands across all nodes in a Windows Failover Cluster.

Commands are wrapped with:

```powershell
Invoke-Command -ComputerName (Get-ClusterNode).Name
```

---

# Keyboard Layout Support

KeyRelay supports typing into systems using different keyboard layouts.

Example layouts:

- en-US
- de-DE
- fr-FR
- es-ES

KeyRelay temporarily switches layouts during typing and restores the original layout afterward.

---

# Configuration Files

KeyRelay stores its configuration files in:

Documents\KeyRelay

Files:

- KeyRelay.commands.json
- KeyRelay.history.json
- KeyRelay.settings.json

---

# Contributing

Contributions and improvements are welcome.

Submit issues or command packs via:

https://github.com/DellProSupportGse/Tools
