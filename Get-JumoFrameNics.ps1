function Get-JumboFrameNICs {
    $nics = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
    $jumboFrameNICs = @()

    foreach ($nic in $nics) {
        $jumboFrame = Get-NetAdapterAdvancedProperty -Name $nic.Name -RegistryKeyword "*JumboPacket*" | Where-Object { $_.DisplayName -eq "Jumbo Packet" }
        if ($jumboFrame.RegistryValue -eq 9014) {
            $jumboFrameNICs += $nic.Name
        }
    }

    return $jumboFrameNICs
}