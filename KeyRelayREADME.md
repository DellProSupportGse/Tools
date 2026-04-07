# KeyRelay

Version: KeyRelay v1.16

KeyRelay is a PowerShell GUI tool designed to send commands or text into applications that do not support paste operations.

This tool is especially useful when working with:

- iDRAC virtual consoles
- KVM consoles
- Serial sessions
- Restricted remote shells
- Secure administrative terminals

KeyRelay safely types commands using a configurable typing engine and includes command libraries, history tracking, selective send, preview mode, and PowerShell-aware editing enhancements.

* * *

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
- Selective send of highlighted text
- Preview Before Typing mode
- Automatic reset of Run on Cluster Nodes after each run
- Built-in GitHub issue link for bug reporting
- PowerShell Tab completion in the editor

* * *

# Command Libraries

KeyRelay supports multiple command sources.

## My Commands

Your personal command library stored locally.

Location:

`Documents\KeyRelay\KeyRelay.commands.json`

Categories help organize commands.

* * *

## Shared Commands

Commands can be downloaded dynamically from GitHub.

Repository:

`https://github.com/DellProSupportGse/Tools`

Shared commands include examples for:

- Windows Server management
- Azure Local troubleshooting
- Failover cluster diagnostics
- Hyper-V administration
- Network ATC configuration

Descriptions are displayed using tooltips.

* * *

# Search

The search bar filters commands in real time.

Search works across:

- My Commands
- Shared Commands
- History

Results update automatically while typing.

* * *

# Command Editor

Commands can be managed directly from the interface.

Right-click a command in My Commands to access:

- Copy Command
- Edit Command
- Remove Command
- Remove Category

The main editor also supports PowerShell Tab completion for faster command authoring.

* * *

# Typing Engine

KeyRelay uses the Windows SendKeys API to simulate typing.

Configurable options include:

| Setting | Description |
|---|---|
| Start Delay | Time before typing begins |
| Per-Key Delay | Delay between characters |
| Between Lines | Delay between command lines |
| Press Enter After Each Line | Sends Enter after each line |
| Target Lang | Temporarily switches keyboard layout while typing |

Typing can be cancelled using the STOP button.

## Selective Send

If text is highlighted in the main editor, KeyRelay will type only the selected portion.

If nothing is selected, KeyRelay types the entire editor contents.

## Preview Before Typing

When enabled, Preview Before Typing shows the exact text that will be sent before typing begins.

The preview indicates:

- whether the full editor or only the selected text will be sent
- whether Run on Cluster Nodes wrapping will be applied
- whether Enter After Each Line is enabled

This helps prevent accidental sends.

* * *

# Cluster Mode

When enabled, KeyRelay executes commands across all nodes in a Windows Failover Cluster.

Commands are wrapped with:

```powershell
Invoke-Command -ComputerName (Get-ClusterNode).Name -ScriptBlock { ... }
