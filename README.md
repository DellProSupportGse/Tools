# Tools
  NOTE: All tools should be run from ISE as administorator unless otherwise noted. 

### Support
Kindly be advised that this code is being offered as-is and Dell will not provide any support in using these tools. However, if you encounter any issues, we would appreciate it if you could submit them under the "Issues" section.
  

-------------------------------------------------------------------------------------------------------------------------------------------------
## Tool Box
Tool Box is a menu of all the tools to run them from one place
	 
   ![alt text](readme/toolbox_v1.1.jpg)
   
### Usage
Copy the below powershell code and paste into PowerShell
```Powershell
Echo ToolBox;[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="ToolBox";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/ToolBox.ps1'));Invoke-ToolBox
``` 
-------------------------------------------------------------------------------------------------------------------------------------------------
## AzHCIUrlChecker
   This script checks the URLs that the Azure Stack HCI operating system may need to access as per Microsoft Doc: 
	https://docs.microsoft.com/en-us/azure-stack/hci/concepts/firewall-requirements
	
### Usage
Copy the below powershell code and paste into PowerShell
```Powershell
Echo AzHCIUrlChecker;[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="AzHCIUrlChecker";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/AzHCIUrlChecker.ps1'));Invoke-AzHCIUrlChecker
``` 
-------------------------------------------------------------------------------------------------------------------------------------------------
## BOILER
   Filters the CBS/DISM logs for Errors/Fails/Warnings to quickly identify failing KB's, Language Tags or
   corruption plus, it provides Suggested fixes.
   
   ![alt text](readme/boiler.jpg)
   
   ### Documentation:
    1. Copy/Paste PowerShell code below
    2. Answer the Rady to run? Y/N
    3. Provide the log to analize in the popup
          - Supports running locally or remotly by feeding it a ZIP file of the logs or just log file.
    4. Review the output for the finds and suggested fixes
    
   ### Supported Scenarios:
    - Failing KBs
        Shows any KBs that are failing to install, provides the link to download them if available and the how to DISM install it for best success.
    - Failing Language Packs
        Shows any language tag that is failing with the process to download and install to repair it
    - Corruption identified by the log
        Show any corruption identified in the log and the steps to restore health with eval ISO
    - Display Errors, Fails and Warnings
        If no other scenario is found but we still see Errors, Fails and Warnings then they are displayed
    
   ### PowerShell
```Powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="BOILER";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/BOILER.ps1'));Invoke-BOILER
```   
  
-------------------------------------------------------------------------------------------------------------------------------------------------
## DART
   **D**ell **A**utomated se**R**ver upda**T**er is a Windows Failover Cluster and HCI/S2D aware tool that will automatically download and 
   install Windows Updates, Drivers/Firmware on Dell Servers.
  
  ![alt text](readme/dart.jpg)
  
  How To Use:
    From PowerShell as admin execute the following:
```Powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="DART";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/DART.ps1'));Invoke-DART
```

### Documentation:
   1. Checks to make sure your running on a Dell server
   2. Checks to see if have the latest Dell System Update is installed
   3. If not then it downloads and installs the latest version of DSU
   4. Is Azure Stack HCI (Storage Spaces Direct Ready Node or AX node)
      - We download and extract the AZHCI-Catalog to use with DSU
      - We Pause & Drain the node and Enable Storage Maintenance Mode
      - Installs Windows Updates
      - Runs DSU
        - No reboot required: We resume the node, disable Storage Maintenance Mode and show Installation Report
        - Reboot Required: We setup a logon task that will resume the node and disable Storage Maintenance Mode after the reboot and logon
        - Failed Update: We show you the failed update and exit so we can look into the errors and decide how to proceed.
   6. Is Cluster member
      - We Pause & Drain the node and Enable Storage Maintenance Mode
      - Installs Windows Updates
      - Runs DSU
        - No reboot required: We resume the node and show Installation Report
        - Reboot Required: We setup a logon task that will resume the node after the reboot and logon
        - Failed Update: We show you the failed update and exit so we can look into the errors and decide how to proceed.
   8. Is Regular Power Edge Server
      - Installs Windows Updates 
      - Runs DSU
        - No reboot required: Show Installation Report
        - Failed Update: We show you the failed update and exit so we can look into the errors and decide how to proceed.
   
   Transcript Logging: C:\ProgramData\Dell\DART
   
   Use -IgnoreChecks:$True to install updates without suspending cluster node or enabling storage maintenance mode for Azure Stack HCI
   
-------------------------------------------------------------------------------------------------------------------------------------------------
## FLEP
   
   This tool is used to filter Windows event logs.
 
 ![alt text](readme/FLEP.jpg)
   
  ### Supported Scenarios:
    
      1 Filter System Event logs
        Filters the system event log for the 24 most common events 13,20,28,41,57,129,153,134,301,1001,1017,1018,1135,5120,6003-6009
      2 Filter for 505 Events
        Filters the Microsoft-Windows-Storage-Storport/Operational event logs for event id 505 to be able to see S2D/HCI storage latancy buckets
    
   ### PowerShell
```Powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="FLEP";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/FLEP.ps1'));Invoke-FLEP
```  
   
-------------------------------------------------------------------------------------------------------------------------------------------------
## LogCollector
   
   This tool is used to collect all the logs Switches, Servers and OS
   
   ![alt text](readme/logcollector_v1.28.jpg)
   
   How To Use: 
      From PowerShell as admin execute the following and follow the prompts:
```Powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="LogCollector";$repo="PowershellScripts"'+(new-object System.net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/LogCollector.ps1'));Invoke-LogCollector
```
-------------------------------------------------------------------------------------------------------------------------------------------------
## GetShowTech
   
   This tool is used to collect Dell switch logs
   
   How To Use: 
      From PowerShell as admin execute the following and follow the prompts:
```Powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="GetShowTech";$repo="PowershellScripts"'+(new-object System.net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/GetShowTech.ps1'));Invoke-GetShowTech
```
-------------------------------------------------------------------------------------------------------------------------------------------------
## Run SDDC
 How To Use:
    From ISE or PowerShell as admin execute the following:
```Powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="SDDC";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/RunSDDC.ps1'));Invoke-RunSDDC
```
-------------------------------------------------------------------------------------------------------------------------------------------------
## SDDC Offline
 
### How To Use with Desktop Experience:
 
    1. Download the SDDC from this link <https://github.com/DellProSupportGse/PrivateCloud.DiagnosticInfo/archive/master.zip>
    2. Copy to the node where you will run it
    3. Open SDDCOffline <https://raw.githubusercontent.com/DellProSupportGse/Tools/main/SDDCOffline.ps1> and copy/paste into ISE on the node where you want to run SDDC
    4. Run the copied code
    5. It will ask you for the location of the downloaded SDDC from step 1 ans 2
    6. The rest will run as normal
    
 ### How to use with Server Core/HCI OS:
     1. Download the SDDC from this link <https://github.com/DellProSupportGse/PrivateCloud.DiagnosticInfo/archive/master.zip>
     2. Right click and copy the downloaded master.zip
     3. RDP into the node and open Notepad
     4. Click Open and browse to the folder you wish to paste the master.zip and then paste it
     5. Open SDDCOffline <https://raw.githubusercontent.com/DellProSupportGse/Tools/main/SDDCOffline.ps1> from a machine with a web brower and copy the code
     6. Switch back to the Server Core/HCI node and paste it into a PowerShell session
     7. It will ask you for the location of the downloaded SDDC from step 1 ans 2
     8. The rest will run as normal
   
-------------------------------------------------------------------------------------------------------------------------------------------------
## TSR Collector
   This tool is used to collect TSRs from
    all nodes in a cluster"

  How To Use:
    From ISE or PowerShell as admin execute the following:
```Powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="TSRCollector";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/TSRCollector.ps1'));Invoke-TSRCollector
```
-------------------------------------------------------------------------------------------------------------------------------------------------
## FLCkr
   **FL**tmc **C**hec**k**e**r**
   This tool lookups up filter drivers in Microsoft's known good list
   URL: https://raw.githubusercontent.com/MicrosoftDocs/windows-driver-docs/staging/windows-driver-docs-pr/ifs/allocated-altitudes.md
   
   How To Use: 
      From ISE or PowerShell as admin execute the following and follow the prompts:
```Powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="FLCkr";$repo="PowershellScripts"'+(new-object System.net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/FLCkr.ps1'));Invoke-FLCkr
```
-------------------------------------------------------------------------------------------------------------------------------------------------

## Convert-Etl2Pcap
Convert ETL network traces to PCap for use with WireShark
   
### Usage
Copy the below powershell code and paste into PowerShell
```Powershell
Echo ToolBox;[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="Convert-Etl2Pcap";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://raw.githubusercontent.com/DellProSupportGse/Tools/main/Convert-Etl2Pcap.ps1'));Invoke-ETL2PCAP
``` 
-------------------------------------------------------------------------------------------------------------------------------------------------

### Report problems or provide feedback
If you run into any problems or would like to provide feedback, please open an issue here https://github.com/DellProSupportGse/Tools/issues
