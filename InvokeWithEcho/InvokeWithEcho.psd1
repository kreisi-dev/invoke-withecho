@{
    RootModule        = 'InvokeWithEcho.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = '4a654f92-8f7b-4878-854f-67f1402cdb30'
    Author            = 'kreisi'
    Description       = 'ECHO ON für PowerShell: führt einen ScriptBlock aus und loggt vorher den Befehlstext samt Variablenwerten — ideal in Kombination mit Start-Transcript.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('Invoke-WithEcho')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('logging', 'echo', 'transcript', 'trace')
            ProjectUri = 'https://github.com/kreisi/invoke-withecho'
        }
    }
}
