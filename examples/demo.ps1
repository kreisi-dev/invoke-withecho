# Demo: Invoke-WithEcho in Kombination mit Start-Transcript.
# Aufruf:  pwsh -NoProfile -File examples/demo.ps1 [-TranscriptPath <pfad>]
param(
    [string] $TranscriptPath = (Join-Path ([System.IO.Path]::GetTempPath()) 'invoke-withecho-demo.log')
)

Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'InvokeWithEcho', 'InvokeWithEcho.psd1') -Force

Start-Transcript -Path $TranscriptPath -Force | Out-Null
try {
    $quellPfad = $PSScriptRoot
    $muster    = '*.ps1'

    $dateien = Invoke-WithEcho { Get-ChildItem $quellPfad -Filter $muster }

    Invoke-WithEcho {
        $dateien | ForEach-Object { "gefunden: $($_.Name)" }
    }

    $langerText = 'Lorem ipsum dolor sit amet, ' * 10
    $laenge = Invoke-WithEcho { $langerText.Length }
    "Länge: $laenge"
}
finally {
    Stop-Transcript | Out-Null
}

"`nTranscript geschrieben nach: $TranscriptPath"
