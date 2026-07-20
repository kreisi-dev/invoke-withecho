@{
    RootModule        = 'InvokeWithEcho.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '4a654f92-8f7b-4878-854f-67f1402cdb30'
    Author            = 'kreisi'
    Description       = 'ECHO ON for PowerShell: runs a script block and logs the command text and variable values beforehand — ideal in combination with Start-Transcript.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Invoke-WithEcho')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('logging', 'echo', 'transcript', 'trace')
            ProjectUri = 'https://github.com/kreisi-dev/invoke-withecho'
        }
    }
}
