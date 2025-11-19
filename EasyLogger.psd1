@{
    # Module manifest for EasyLogger
    RootModule        = 'EasyLogger.psm1'
    ModuleVersion     = '1.1.0'
    GUID              = '8c7c8d3c-3f5d-4a1b-9f39-2a9f0c8a5c12'

    Author            = 'msyslab'
    CompanyName       = 'Community'
    Copyright         = '(c) MIT License.'

    Description       = 'EasyLogger is a lightweight PowerShell logging module providing readable, structured, colored and multi-buffer logs, easy to export to files.'

    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Initialize-EasyLogger',
        'Write-Log',
        'Write-LogProgress',
        'Get-LogText',
        'Get-LogObjects',
        'Clear-LogBuffer',
        'Save-LogToFile',
        'Get-LogBufferIds',
        'Stop-LogProgress',
        'Get-LogSummary',
        'Export-LogBuffers',
        'Import-LogBuffers'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('Logging', 'EasyLogger', 'PowerShell', 'Module')
            LicenseUri   = 'https://opensource.org/licenses/MIT'
            ProjectUri   = ''
            IconUri      = ''
            ReleaseNotes = 'Initial public version of EasyLogger.'
        }
    }
}
