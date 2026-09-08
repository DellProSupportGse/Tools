
# KeyRelay Quick Start

**Version:** KeyRelay v1.13

KeyRelay is a lightweight PowerShell GUI tool designed to send commands to applications that do not allow pasting, such as remote consoles or restricted terminals.

---

# 1. Download

Download the latest version from the repository:

https://github.com/DellProSupportGse/Tools

Save the script locally:

KeyRelay.ps1

---

# 2. Run KeyRelay

Open PowerShell and run:

```powershell
.\KeyRelay.ps1
Invoke-KeyRelay
```

---

# 3. Basic Usage

1. Paste your command into the editor.
2. Set the Start Delay.
3. Click **Type It**.
4. Switch to the target window before the delay expires.

KeyRelay will safely type the command into the target application.

---

# 4. Command Tabs

KeyRelay organizes commands using three tabs.

| Tab | Description |
|----|----|
| My Commands | Your personal saved command library |
| Shared | Commands downloaded from GitHub |
| History | Recently executed commands |

Double-click a command to insert it into the editor.

---

# 5. Search Commands

Use the **Search** box to quickly filter commands.

Search works across:

- My Commands
- Shared Commands
- History

Results update automatically as you type.

---

# 6. Add Your Own Commands

Click **Add Command** and enter:

- Category
- Display Name
- Command text

Commands are stored locally in:

Documents\KeyRelay\KeyRelay.commands.json

---

# 7. Add Commands From History

Commands executed through KeyRelay are automatically saved.

To save one permanently:

1. Select a command in History
2. Click **Add From History**
3. Enter a name and category

---

# 8. Shared Commands

KeyRelay downloads shared command libraries from GitHub.

Repository:

https://github.com/DellProSupportGse/Tools

Shared commands include examples for:

- Windows Server
- Azure Local
- Failover Clustering
- Hyper-V
- Network ATC

Hover over a command to see its description.

---

# 9. Run Commands on Cluster Nodes

Enable **Run on Cluster Nodes** to execute commands across all nodes in a Windows Failover Cluster.

KeyRelay automatically wraps the command with:

```powershell
Invoke-Command -ComputerName (Get-ClusterNode).Name -ScriptBlock { <command> }
```

---

# 10. Keyboard Layout Targeting

Some remote consoles use different keyboard layouts.

You can specify a target layout such as:

- en-US
- fr-FR
- de-DE

KeyRelay temporarily switches layouts before typing and restores the original layout afterward.
