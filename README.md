# Tools
#### All tools are run from ISE as administorator. They do not work from PowerShell. 
-------------------------------------------------------------------------------------------------------------------------------------------------
## Dell System Updater
   This tool will automatically download and 
   install Drivers/Firmware on Dell Servers
  
  How To Use:
    From ISE or PowerShell as admin execute the following:
```Powershell
iex ('$module="DellSystemUpdater";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/DellSystemUpdater.ps1'));Invoke-DellSystemUpdater
```

### Documentation:
   1. Checks to see if Dell System Update is installed
   2. If not then it downloads and installs DSU
   3. Gathers the Server model
   4. Is Azure Stack HCI (Storage Spaces Direct Ready Node or AX node)
      - We download and extract the AZHCI-Catalog to use for DSU
      - We Pause & Drain the node and Enable Storage Maintenance Mode
      - Run DSU
        - No reboot required: We resume the node, disable Storage Maintenance Mode and show Installation Report
        - Reboot Required: We setup a logon task that will resume the node and disable Storage Maintenance Mode after the reboot and logon
        - Failed Update: We show you the failed update and exit so we can look into the errors and decide how to proceed.
   6. Is Cluster member
      - We Pause & Drain the node and Enable Storage Maintenance Mode
      - Run DSU
        - No reboot required: We resume the node and show Installation Report
        - Reboot Required: We setup a logon task that will resume the node after the reboot and logon
        - Failed Update: We show you the failed update and exit so we can look into the errors and decide how to proceed.
   8. Is Regual Power Edge
      - Run DSU
        - No reboot required: Show Installation Report
        - Failed Update: We show you the failed update and exit so we can look into the errors and decide how to proceed.
-------------------------------------------------------------------------------------------------------------------------------------------------
## FLCkr
   This tool lookups up filter drivers in Microsoft's known good list
   URL: https://raw.githubusercontent.com/MicrosoftDocs/windows-driver-docs/staging/windows-driver-docs-pr/ifs/allocated-altitudes.md
   
   How To Use: 
      From ISE or PowerShell as admin execute the following and follow the prompts:
```Powershell
iex ('$module="FLCkr";$repo="PowershellScripts"'+(new-object System.net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/FLCkr.ps1'));Invoke-FLCkr
```
-------------------------------------------------------------------------------------------------------------------------------------------------
## Run SDDC
 How To Use:
    From ISE or PowerShell as admin execute the following:
```Powershell
iex ('$module="SDDC";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/RunSDDC.ps1'));Invoke-SDDC
```
---
## TSR Collector
   This tool is used to collect TSRs from
    all nodes in a cluster"

  How To Use:
    From ISE or PowerShell as admin execute the following:
```Powershell
iex ('$module="TSRCollector";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/TSRCollector.ps1'));Invoke-TSRCollector
```
-------------------------------------------------------------------------------------------------------------------------------------------------

