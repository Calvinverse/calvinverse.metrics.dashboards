[CmdletBinding()]
param(
    [string] $consulDatacenter = 'calvinverse-01',
    [string] $consulPort = '8500',
    [string] $consulServerAddress = $( throw 'Please specify the IP address for the consul server' ),
    [string] $configPath = $PSScriptRoot
)

Write-Verbose "Set-ConsulKV: param consulDatacenter = $consulDatacenter"
Write-Verbose "Set-ConsulKV: param port = $consulPort"
Write-Verbose "Set-ConsulKV: param serverIp = $consulServerAddress"
Write-Verbose "Set-ConsulKV: param configPath = $configPath"

$ErrorActionPreference = 'Stop'
$commonParameterSwitches =
    @{
        Verbose = $PSBoundParameters.ContainsKey('Verbose');
        ErrorAction = "Stop"
    }

# --------------------------- START FUNCTIONS --------------------------------

# --------------------------- END FUNCTIONS ----------------------------------

$tempPath = Join-Path $PSScriptRoot 'temp'
if (-not (Test-Path $tempPath))
{
    New-Item -Path $tempPath -ItemType Directory | Out-Null
}

try
{
    $yamlModule = 'powershell-yaml'
    if (-not (Get-Module -ListAvailable -Name $yamlModule))
    {
        Install-Module -Name $yamlModule -Scope CurrentUser
    }

    if (-not (Get-module -Name $yamlModule))
    {
        Import-Module -Name $yamlModule -Scope Local
    }

    $webClient = New-Object System.Net.WebClient
    try
    {
        $kvFiles = Get-ChildItem -Path "$($configPath)\*" -Recurse -Include *.yaml
        foreach($kvFile in $kvFiles)
        {
            Write-Output "Processing $($kvFile.FullName) ..."
            $yaml = ConvertFrom-Yaml -Yaml (Get-Content $kvFile.FullName | Out-String)

            # The Yaml object is a hashtable, that contains a single item with 'config' as key.
            # The value is a list of hashtables, each of which store two values, one for the 'key'
            # entry and one for the 'value' or 'file' entries.
            foreach($entry in $yaml['config'])
            {
                $key = $entry['key']
                if ($entry.ContainsKey('file'))
                {
                    $path = Join-Path (Split-Path -Parent -Path $kvFile.FullName) $entry['file']
                    $value = Get-Content -Path $path | Out-String
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($value)
                }
                else
                {
                    $value = $entry['value'].ToString()
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($value)
                }

                Write-Output "Writing k-v with key: $($key) - value: $($value) ... "

                $url = "http://$($consulServerAddress):$($consulPort)/v1/kv/$($key)"
                $responseBytes = $webClient.UploadData($url, "PUT", $bytes)
                $response = [System.Text.Encoding]::ASCII.GetString($responseBytes)
                Write-Output "Wrote k-v with key: $($key) - value: $($value). Response: $($response)"
            }
        }
    }
    finally
    {
        $webClient.Dispose()
    }
}
catch
{
    $currentErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    try
    {
        Write-Error $errorRecord.Exception
        Write-Error $errorRecord.ScriptStackTrace
        Write-Error $errorRecord.InvocationInfo.PositionMessage
    }
    finally
    {
        $ErrorActionPreference = $currentErrorActionPreference
    }

    # rethrow the error
    throw $_.Exception
}
