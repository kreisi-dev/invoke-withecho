# Demo: Invoke-WithEcho combined with Start-Transcript.
# Usage:  pwsh -NoProfile -File examples/demo.ps1 [-TranscriptPath <path>]
param(
    [string] $TranscriptPath = (Join-Path ([System.IO.Path]::GetTempPath()) 'Invoke-WithEcho-demo.log')
)

# Single -ChildPath with separators: -AdditionalChildPath does not exist in PowerShell 5.1
Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../InvokeWithEcho/InvokeWithEcho.psd1') -Force

Start-Transcript -Path $TranscriptPath -Force | Out-Null
try {
    $sourcePath = $PSScriptRoot
    $pattern    = '*.ps1'

    $files = Invoke-WithEcho { Get-ChildItem $sourcePath -Filter $pattern }

    Invoke-WithEcho {
        $files | ForEach-Object { "found: $($_.Name)" }
    }

    $longText = 'Lorem ipsum dolor sit amet, ' * 10
    $length = Invoke-WithEcho { $longText.Length }
    "Length: $length"
}
finally {
    Stop-Transcript | Out-Null
}

"`nTranscript written to: $TranscriptPath"
