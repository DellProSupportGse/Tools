# KeyRelay v1.7

**KeyRelay** is a PowerShell GUI tool that allows you to send commands
to applications or consoles that **do not allow paste operations** (for
example: RDP sessions, restricted consoles, BIOS tools, lab
environments, etc.).

Instead of pasting text, KeyRelay **relays keystrokes** one character at
a time using simulated keyboard input.

This makes it extremely useful for:

-   Windows Server labs
-   Cluster management consoles
-   RDP sessions with restricted paste
-   Training environments
-   Secure terminals
-   Remote systems with keyboard layout differences

------------------------------------------------------------------------

# Key Features

## Keystroke Relay

KeyRelay types commands exactly as if they were typed manually.

Features include:

-   Adjustable **Start Delay**
-   Adjustable **Per-Key Delay**
-   Adjustable **Between-Line Delay**
-   Optional **Press Enter After Each Line**

------------------------------------------------------------------------

# Command Library

KeyRelay includes a built‑in **command library** organized by category.

Commands are stored in:

    Documents\KeyRelay\KeyRelay.commands.json

Capabilities:

-   Add new commands
-   Add commands from history
-   Edit existing commands
-   Remove commands
-   Remove entire categories
-   Commands automatically sort alphabetically

Double‑clicking a command loads it into the editor.

------------------------------------------------------------------------

# Right‑Click Command Editing

Commands can be managed directly in the command tree.

Right‑click options include:

    Edit Command
    Remove Command
    Remove Category

Editing opens the command dialog with the command pre‑filled so it can
be modified and saved.

------------------------------------------------------------------------

# Command History

KeyRelay keeps a history of previously executed commands.

History is stored in:

    Documents\KeyRelay\KeyRelay.history.json

Features:

-   Last **10 commands** stored
-   Double‑click history to reload into the editor
-   Add history items directly to the command library
-   Clear history with confirmation prompt

------------------------------------------------------------------------

# Cluster Execution Mode

KeyRelay can automatically run commands across cluster nodes.

When **Run on Cluster Nodes** is enabled, commands are automatically
wrapped with:

``` powershell
Invoke-Command -ComputerName (Get-ClusterNode).Name -ScriptBlock { command }
```

This allows administrators to easily execute commands across all cluster
nodes.

------------------------------------------------------------------------

# Target Language Field

Enter the **Windows language culture code** for the keyboard layout you want the remote system to use.

Examples:

| Language | Culture Code |
|--------|--------|
| US English | `en-US` |
| UK English | `en-GB` |
| French (France) | `fr-FR` |
| French (Canada) | `fr-CA` |
| German | `de-DE` |
| Spanish | `es-ES` |
| Japanese | `ja-JP` |

When typing begins, KeyRelay will:

1. Temporarily switch the keyboard layout to the specified culture.
2. Send the keystrokes.
3. Restore your original keyboard layout when finished.

This ensures that characters are sent **exactly as the target system expects**, even when keyboard layouts differ.

---

## Finding the Keyboard Layout on a Target System

To determine the keyboard layout currently in use on a system, run the following command in PowerShell:

```powershell
([system.windows.forms.inputlanguage]::DefaultInputLanguage).culture.name
```

------------------------------------------------------------------------

# Window Control Features

## Always On Top

Keeps KeyRelay visible while interacting with other windows.

## Select Previous Window on Type

Optionally switches focus back to the previous window before typing
begins.

------------------------------------------------------------------------

# Safety Controls

## Start Delay

Allows time to switch to the target window before typing begins.

## STOP Button

Stops the typing process immediately.

While typing:

-   **Type It button is disabled**
-   **STOP button is enabled**

------------------------------------------------------------------------

# Command Storage Format

Commands are stored in JSON format:

``` json
{
  "Commands": [
    {
      "Name": "Storage",
      "Children": [
        {
          "Name": "Get Storage Pools",
          "Command": "Get-StoragePool -IsPrimordial $False"
        }
      ]
    }
  ]
}
```

------------------------------------------------------------------------

# Settings Storage

User preferences are stored in:

    Documents\KeyRelay\KeyRelay.settings.json

Saved settings include:

-   Start delay
-   Key delay
-   Line delay
-   Enter per line
-   Always on top
-   Cluster execution
-   Window focus behavior

------------------------------------------------------------------------

# File Locations

  File                     Purpose
  ------------------------ -----------------
  KeyRelay.commands.json   Command library
  KeyRelay.history.json    Command history
  KeyRelay.settings.json   User settings

All files are stored in:

    Documents\KeyRelay\

------------------------------------------------------------------------

# Quick Start

1.  Run:

``` powershell
Invoke-KeyRelay
```

2.  Paste or type the command into the editor.
3.  Click **Type It**.
4.  Switch to the target window before the start delay expires.

KeyRelay will relay the command as keyboard input.

------------------------------------------------------------------------

# Example

Example command entered in KeyRelay:

``` powershell
Get-ClusterNode
```

If **Run on Cluster Nodes** is enabled, KeyRelay will type:

``` powershell
Invoke-Command -ComputerName (Get-ClusterNode).Name -ScriptBlock { Get-ClusterNode }
```

------------------------------------------------------------------------

# Version

Current Version:

    KeyRelay v1.7

------------------------------------------------------------------------

# Author

Jim Gandy

------------------------------------------------------------------------

# Repository

https://github.com/DellProSupportGse/Tools
