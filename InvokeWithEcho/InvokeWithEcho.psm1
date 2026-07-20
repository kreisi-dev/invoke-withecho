# Automatic or runtime-bound variables whose value adds no insight to the echo
# log or does not exist yet at call time (e.g. $_ inside a pipeline).
$script:SkipVariables = @(
    '_', 'PSItem', 'null', 'true', 'false', 'args', 'input', 'this',
    'foreach', 'switch', 'PSCmdlet', 'MyInvocation', 'PSBoundParameters',
    'PSScriptRoot', 'PSCommandPath', 'Error', 'LASTEXITCODE', 'PID',
    'HOME', 'PWD', 'Host', 'ExecutionContext', 'PROFILE'
)

# Dot-source every function file under Public/ and Private/, then export only the
# public functions. New public functions must also be listed in FunctionsToExport
# in the module manifest (InvokeWithEcho.psd1) to be visible to consumers.

$Public  = @(Get-ChildItem -Path "$PSScriptRoot/Public/*.ps1"  -ErrorAction SilentlyContinue)
$Private = @(Get-ChildItem -Path "$PSScriptRoot/Private/*.ps1" -ErrorAction SilentlyContinue)

foreach ($file in @($Public + $Private)) {
    try {
        . $file.FullName
    } catch {
        throw "Failed to import function $($file.FullName): $_"
    }
}

if ($Public.Count -gt 0) {
    Export-ModuleMember -Function $Public.BaseName
}
