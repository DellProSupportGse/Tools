# KeyRelay

Version: KeyRelay v1.17

KeyRelay is a PowerShell GUI tool designed to send commands or text into applications that do not support paste operations.

This tool is especially useful when working with:

- iDRAC virtual consoles
- KVM consoles
- Serial sessions
- Restricted remote shells
- Secure administrative terminals

KeyRelay safely types commands using a configurable typing engine and includes command libraries, history tracking, selective send, preview mode, PowerShell-aware editing enhancements, command descriptions, and import/export support.

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
- Selective send of highlighted text
- Preview Before Typing mode
- Automatic reset of Run on Cluster Nodes after each run
- Built-in GitHub issue link for bug reporting
- PowerShell Tab completion in the editor
- Command descriptions in My Commands
- Import and export support for My Commands

---

# Command Libraries

KeyRelay supports multiple command sources.

## My Commands

Your personal command library is stored locally.

Location:

`Documents\KeyRelay\KeyRelay.commands.json`

Categories help organize commands.

Each command in **My Commands** can now include:

- Display name
- Description
- Command text

Descriptions are shown as tooltips in the **My Commands** tree to make it easier to understand what each command does before sending it.

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

---

# Search

The search bar filters commands in real time.

Search works across:

- My Commands
- Shared Commands
- History

Results update automatically while typing.

For command libraries, search can match against:

- Command name
- Command text
- Description text

---

# Command Editor

Commands can be managed directly from the interface.

Right-click a command in My Commands to access:

- Copy Command
- Edit Command
- Remove Command
- Remove Category

The Add / Edit Command dialog supports:

- Category
- Display Name
- Description
- Command text

The main editor also supports PowerShell Tab completion for faster command authoring.

## PowerShell Tab Completion

KeyRelay includes PowerShell-aware tab completion inside the command editor.

Pressing **Tab** will:

- Auto-complete cmdlets, parameters, and variables
- Cycle through multiple matches on repeated Tab presses
- Replace only the current token being typed

Example:

Typing:

```powershell
Get-NetAdap
