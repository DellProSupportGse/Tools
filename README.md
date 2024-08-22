# Tools
  NOTE: All tools should be run from ISE as administorator unless otherwise noted. 

### Licensing/Support
We'd like to inform you that this code is freely available under the [MIT License](https://github.com/DellProSupportGse/Tools/blob/main/License) and is utilized by numerous individuals worldwide on a daily basis. Should you encounter any challenges, we kindly request you to submit them via the designated "Issues" section. Your contributions are greatly appreciated.

-------------------------------------------------------------------------------------------------------------------------------------------------
## Tool Box
Tool Box is a menu of all the tools to run them from one place
	 
   ![alt text](readme/toolbox_v1.1.jpg)
   
### Usage
Copy the below powershell code and paste into PowerShell
```Powershell
Echo ToolBox;[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="ToolBox";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('http'+'s://raw.githubusercontent.com/DellProSupportGse/Tools/main/ToolBox.ps1'));Invoke-ToolBox
```
### Issue:
##### If you see the following error:
![alt text](readme/ToolBoxProxyError.jpg)
### Solution:
##### Run this in the PowerShell windows before running the command
 	$browser = New-Object System.Net.WebClient
	$browser.Proxy.Credentials =[System.Net.CredentialCache]::DefaultNetworkCredentials
-------------------------------------------------------------------------------------------------------------------------------------------------
## AzHCIUrlChecker
   This script checks the URLs that the Azure Stack HCI operating system may need to access as per Microsoft Doc: 
	https://docs.microsoft.com/en-us/azure-stack/hci/concepts/firewall-requirements
	
### Usage
Copy the below powershell code and paste into PowerShell
```Powershell
Echo AzHCIUrlChecker;[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="AzHCIUrlChecker";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('http'+'s://raw.githubusercontent.com/DellProSupportGse/Tools/main/AzHCIUrlChecker.ps1'));Invoke-AzHCIUrlChecker
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
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="BOILER";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('http'+'s://raw.githubusercontent.com/DellProSupportGse/Tools/main/BOILER.ps1'));Invoke-BOILER
```   
  
-------------------------------------------------------------------------------------------------------------------------------------------------
## DART
   **D**ell **A**utomated se**R**ver upda**T**er is a Windows Failover Cluster and HCI/S2D aware tool that will automatically download and 
   install Windows Updates, Drivers/Firmware on Dell Servers.
  
  ![alt text](readme/dart.jpg)
  
  How To Use:
    From PowerShell as admin execute the following:
```Powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="DART";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('http'+'s://raw.githubusercontent.com/DellProSupportGse/Tools/main/DART.ps1'));Invoke-DART
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
   
   Use -IgnoreVersion:$True to ignore the block for for 23H2 prior to the cluster deployment
   
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
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="FLEP";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('http'+'s://raw.githubusercontent.com/DellProSupportGse/Tools/main/FLEP.ps1'));Invoke-FLEP
```  
   
-------------------------------------------------------------------------------------------------------------------------------------------------
## LogCollector
   
   This tool is used to collect all the logs Switches, Servers and OS
   
   ![alt text](readme/logcollector_v1.28.jpg)
   
   How To Use: 
      From PowerShell as admin execute the following and follow the prompts:
```Powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="LogCollector";$repo="PowershellScripts"'+(new-object System.net.webclient).DownloadString('http'+'s://raw.githubusercontent.com/DellProSupportGse/Tools/main/LogCollector.ps1'));Invoke-LogCollector
```
-------------------------------------------------------------------------------------------------------------------------------------------------
## GetShowTech
   
   This tool is used to collect Dell switch logs
   
   How To Use: 
      From PowerShell as admin execute the following and follow the prompts:
```Powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="GetShowTech";$repo="PowershellScripts"'+(new-object System.net.webclient).DownloadString('http'+'s://raw.githubusercontent.com/DellProSupportGse/Tools/main/GetShowTech.ps1'));Invoke-GetShowTech
```
-------------------------------------------------------------------------------------------------------------------------------------------------
## Run SDDC
 How To Use:
    From ISE or PowerShell as admin execute the following:
```Powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="SDDC";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('http'+'s://raw.githubusercontent.com/DellProSupportGse/Tools/main/RunSDDC.ps1'));Invoke-RunSDDC
```
-------------------------------------------------------------------------------------------------------------------------------------------------
## SDDC Offline
 
### How To Use with Desktop Experience:
1. From a machine that has Internet access, download the SDDC master file from here: <https://github.com/DellProSupportGse/PrivateCloud.DiagnosticInfo/archive/master.zip>
2. Right click and copy the downloaded file.
3. Connect to a node of the cluster using RDP.
4. If Sconfig launches, select option 15 to exit to Powershell.
5. Type notepad at the prompt to launch Notepad.
6. From the File menu, select Save As.
7. Browse to the folder where you wish to save the master.zip file and type Ctrl-V to paste it into the folder.
8. Return to the machine with Internet access and browse to https://github.com/DellProSupportGse/Tools.
9. Click SDDCOffline.ps1.
10. Near the upper-right corner of the code window, click Raw to view only the PowerShell code.
11. Type Ctrl-A to select the complete PowerShell script, then Ctrl-C to copy it.
12. Return to the RDP session on the cluster node and paste the copied text directly into PowerShell.
13. Press Enter to begin running the script.
14. Type y at the Ready to run? prompt.
15. Any previous versions of the SDDC tool will be removed automatically.
16. Type y again when asked if the SDDC has been copied locally.
17. Browse to the C:\Dell folder and select the zipped SDDC master file. Click Open.
18. The offline SDDC tool will be extracted to all nodes, and data collection will begin. This will take several minutes.
19. When prompted, type y to remove the downloaded SDDC master file or n to retain it.
20. The zipped output file will be located in C:\users\<current user>\ and will have a name that begins with HealthTest.
    
 ### How to use with Server Core/HCI OS:
1. From a machine that has Internet access, download the SDDC master file from here: <https://github.com/DellProSupportGse/PrivateCloud.DiagnosticInfo/archive/master.zip>
2. Right click and copy the downloaded file.
3. Connect to a node of the cluster using RDP.
4. If Sconfig launches, select option 15 to exit to Powershell.
5. Type notepad at the prompt to launch Notepad.
6. From the File menu, select Save As.
7. Browse to the folder where you wish to save the master.zip file and type Ctrl-V to paste it into the folder.
8. Return to the machine with Internet access and browse to https://github.com/DellProSupportGse/Tools.
9. Click SDDCOffline.ps1.
10. Near the upper-right corner of the code window, click Raw to view only the PowerShell code.
11. Type Ctrl-A to select the complete PowerShell script, then Ctrl-C to copy it.
12. Return to the RDP session on the cluster node and paste the copied text directly into PowerShell.
13. Press Enter to begin running the script.
14. Type y at the Ready to run? prompt.
15. Any previous versions of the SDDC tool will be removed automatically.
16. Type y again when asked if the SDDC has been copied locally.
17. Browse to the C:\Dell folder and select the zipped SDDC master file. Click Open.
18. The offline SDDC tool will be extracted to all nodes, and data collection will begin. This will take several minutes.
19. When prompted, type y to remove the downloaded SDDC master file or n to retain it.
20. The zipped output file will be located in C:\users\<current user>\ and will have a name that begins with HealthTest.	
	   
-------------------------------------------------------------------------------------------------------------------------------------------------
## TSR Collector
   This tool is used to collect TSRs from
    all nodes in a cluster"

  How To Use:
    From ISE or PowerShell as admin execute the following:
```Powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="TSRCollector";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('http'+'s://raw.githubusercontent.com/DellProSupportGse/Tools/main/TSRCollector.ps1'));Invoke-TSRCollector
```
-------------------------------------------------------------------------------------------------------------------------------------------------
## FLCkr
   **FL**tmc **C**hec**k**e**r**
   This tool lookups up filter drivers in Microsoft's known good list
   URL: https://raw.githubusercontent.com/MicrosoftDocs/windows-driver-docs/staging/windows-driver-docs-pr/ifs/allocated-altitudes.md
   
   How To Use: 
      From ISE or PowerShell as admin execute the following and follow the prompts:
```Powershell
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="FLCkr";$repo="PowershellScripts"'+(new-object System.net.webclient).DownloadString('http'+'s://raw.githubusercontent.com/DellProSupportGse/Tools/main/FLCkr.ps1'));Invoke-FLCkr
```
-------------------------------------------------------------------------------------------------------------------------------------------------

## Convert-Etl2Pcap
Convert ETL network traces to PCap for use with WireShark
   
### Usage
Copy the below powershell code and paste into PowerShell
```Powershell
Echo ToolBox;[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="Convert-Etl2Pcap";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('http'+'s://raw.githubusercontent.com/DellProSupportGse/Tools/main/Convert-Etl2Pcap.ps1'));Invoke-ETL2PCAP
``` 
-------------------------------------------------------------------------------------------------------------------------------------------------
## Make ISO
Convert a folder to ISO
   
### Usage
Copy the below powershell code and paste into PowerShell
```Powershell
Echo MakeIso;[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;Invoke-Expression('$module="MakeIso";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('http'+'s://raw.githubusercontent.com/DellProSupportGse/Tools/main/isomaker.ps1'));Invoke-MakeISO
``` 
-------------------------------------------------------------------------------------------------------------------------------------------------

### Report problems or provide feedback
If you run into any problems or would like to provide feedback, please open an issue here https://github.com/DellProSupportGse/Tools/issues
