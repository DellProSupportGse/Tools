# KeyRelay -- Quick Start

This quick guide will help you start using **KeyRelay** in less than a
minute.

------------------------------------------------------------------------

# 1. Launch KeyRelay

Open PowerShell and run:

``` powershell
Echo KeyRelay;[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="KeyRelay";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('http'+'s://raw.githubusercontent.com/DellProSupportGse/Tools/main/KeyRelay.ps1'));Invoke-KeyRelay
```

The **KeyRelay GUI** will appear.

------------------------------------------------------------------------

# 2. Enter a Command

Paste or type the command you want KeyRelay to relay into the **editor
window**.

Example:

``` powershell
Get-ClusterNode
```

You can also load commands by:

-   Double-clicking a command in the **Commands tab**
-   Double-clicking a previous command in the **History tab**

------------------------------------------------------------------------

# 3. Configure Optional Settings

KeyRelay allows several optional controls to fine-tune typing behavior.

  -----------------------------------------------------------------------
  Setting                  Description
  ------------------------ ----------------------------------------------
  Start Delay              Time before typing begins. Gives you time to
                           switch windows.

  Per-Key Delay            Delay between each character typed.

  Between Lines            Delay between command lines.

  Press Enter After Each   Automatically presses Enter after each line.
  Line                     

  Run on Cluster Nodes     Wraps the command using `Invoke-Command` for
                           cluster execution.

  Target Keyboard          Ensures characters are correct for different
                           keyboard layouts.
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# 4. Switch to the Target Window

After clicking **Type It**, switch to the application where the command
should be typed.

Common examples include:

-   RDP sessions
-   iDRAC / KVM consoles
-   Secure terminals
-   Training lab virtual machines

The **Start Delay** gives you time to move focus to that window.

------------------------------------------------------------------------

# 5. Start Typing

Click:

    Type It

KeyRelay will begin sending the command as simulated keyboard input.

While typing:

-   **Type It button is disabled**
-   **STOP button is enabled**

------------------------------------------------------------------------

# 6. Stop Typing

If you need to stop the relay process immediately, click:

    STOP

This cancels the typing operation safely.

------------------------------------------------------------------------

# Tips

✔ Use a **Start Delay of 3--5 seconds** when switching into remote
consoles.\
✔ Increase **Per-Key Delay** if characters are missed in slow
terminals.\
✔ Save frequently used commands in the **Commands library**.\
✔ Use **History** to quickly re-run recently used commands.

------------------------------------------------------------------------

# Where Files Are Stored

KeyRelay stores its data in:

    Documents\KeyRelay\

Files created automatically:

-   `KeyRelay.commands.json`
-   `KeyRelay.history.json`
-   `KeyRelay.settings.json`

------------------------------------------------------------------------

# You're Ready

You can now relay commands into environments where **paste is disabled
or unreliable**.
