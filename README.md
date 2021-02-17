# Tools
All tools are run from ISE as administorator. They do not work from PowerShell. 
[logo]: https://github.com/adam-p/markdown-here/raw/master/src/common/images/icon48.png "Logo Title Text 2"
-------------------------------------------------------------------------------------------------------------------------------------------------
___  ____ _    _       ____ _   _ ____ ___ ____ _  _    _  _ ___  ___  ____ ___ ____ ____ 
|  \ |___ |    |       [__   \_/  [__   |  |___ |\/|    |  | |__] |  \ |__|  |  |___ |__/ 
|__/ |___ |___ |___    ___]   |   ___]  |  |___ |  |    |__| |    |__/ |  |  |  |___ |  \ 
   This tool will automatically download and 
   install Drivers/Firmware on Dell Servers
  
  HowToUse:
    From ISE as admin copy and paste the following to run Dell Sysem Updater
      iex ('$module="DellSystemUpdater";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://github.com/DellProSupportGse/Tools/blob/main/DellSystemUpdater.ps1'));Invoke-DellSystemUpdater

-------------------------------------------------------------------------------------------------------------------------------------------------
  _____ ___ ___    ___     _ _        _           
 |_   _/ __| _ \  / __|___| | |___ __| |_ ___ _ _ 
   | | \__ \   / | (__/ _ \ | / -_) _|  _/ _ \ '_|
   |_| |___/_|_\  \___\___/_|_\___\__|\__\___/_|  
    This tool is used to collect TSRs from
    all nodes in a cluster"

  HowToUse:
    From ISE as admin copy and paste the following to run
      iex ('$module="TSRCollector";$repo="PowershellScripts"'+(new-object net.webclient).DownloadString('https://github.com/DellProSupportGse/Tools/blob/main/TSRCollector.ps1'));Invoke-TSRCollector

-------------------------------------------------------------------------------------------------------------------------------------------------

