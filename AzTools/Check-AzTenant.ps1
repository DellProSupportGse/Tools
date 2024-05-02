# Copyright (c) 2023 Dell Inc. or its subsidiaries. All Rights Reserved.
#
# This software contains the intellectual property of Dell Inc. or is licensed to Dell Inc. from third parties.
# Use of this software and the intellectual property contained therein is expressly limited to the terms and
# conditions of the License Agreement under which it is provided by or on behalf of Dell Inc. or its subsidiaries.

param(
    [Parameter(Mandatory = $true, Position = 0, ValueFromPipelineByPropertyName = $true)]
    [string]
    ${azureCloud},

    [Parameter(Mandatory = $true, Position = 1, ValueFromPipelineByPropertyName = $true)]
    [string]
    ${subscriptionID}

)
Function Invoke-CheckAzTenant{
    function Get-AzureURIs {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)]
            #this script from microsoft, if dynamic get region api is implemented,please use this api to replase this validateSet
            [ValidateSet("AzureCloud", "AzureChinaCloud", "AzureGermanCloud", "AzureUSGovernment")]
            [string] $AzureEnvironment = "AzureCloud"
        )
    
        $commandName = $MyInvocation.MyCommand
    
        $fullUri = "https://management.azure.com/metadata/endpoints?api-version=2023-01-01"
        try {
            $response = Invoke-RestMethod -Uri $fullUri -ErrorAction Stop -UseBasicParsing -TimeoutSec 30 -Verbose
        } catch {
            $message = "[$commandName] Error $($_.Exception)"
            throw $message
        }
        # 6/30/2023 current ece version:10.2306.0.47, and this response name field only AzureCloud,so other AzureEnvironment value can not be used
        $data = $response | Where name -EQ $AzureEnvironment
        if (-not $data) {
            throw New-Object NotImplementedException("Unknown environment type $AzureEnvironment")
        }
    
        # sample @{ GraphUri = "https://graph.windows.net/"; LoginUri = "https://login.microsoftonline.com/"; ManagementServiceUri = "https://management.core.windows.net/"; ARMUri = "https://management.azure.com/" }
        $endpointProperties = @{
            GraphUri = $data.graph
            LoginUri = $data.authentication.loginEndpoint
            ManagementServiceUri = $data.authentication.audiences[0]
            ARMUri = $data.resourceManager
            MsGraphUri = $data.microsoftGraphResourceId
        }
    
        return $endpointProperties
    }
    
    function Get-TenantId
    {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory=$false)]
            [ValidateSet("AzureCloud", "AzureChinaCloud", "AzureGermanCloud", "AzureUSGovernment")]
            [string] $AzureEnvironment = "AzureCloud",
    
            [Parameter(Mandatory=$true)]
            [string] $SubscriptionId
        )
    
        $commandName = $MyInvocation.MyCommand
        $endpoints = Get-AzureURIs -AzureEnvironment $AzureEnvironment
    
        $params = @{
            UseBasicParsing = $true
            ErrorAction     = 'Stop'
            Uri             = $endpoints.ARMUri.TrimEnd('/') + "/subscriptions/${SubscriptionId}?api-version=1.0"
        }
        $response = try { Invoke-WebRequest @params } catch { $_.Exception.Response }
    
        if ($response.StatusCode -eq [System.Net.HttpStatusCode]::NotFound) {
            throw "[$commandName] SubscriptionId $SubscriptionId not found"
        }
    
    
        $contentTypeValues = $response.Headers.GetValues("WWW-Authenticate")
        if ($contentTypeValues) {
            $header = $contentTypeValues[0]
        }
        $guidPattern = "[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}"
        $tenantId = $header.Split(' ') | Where-Object { $_ -like '*authorization_uri*' } | Select-Object -First 1 | ForEach-Object { [Regex]::Matches($_, $guidPattern).Value }
    
        if ([string]::IsNullOrEmpty($tenantId)) {
            throw "[$commandName] Unable to get tenantId for SubscriptionId $SubscriptionId"
        }
    
        return ,$tenantId
    
    }
    
    try {
        $TenantId=Get-TenantId $azureCloud $subscriptionID -Verbose 4>&1 | Where-Object { $_.GetType().Name -ne 'VerboseRecord' }
        return $TenantId
    } catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}
