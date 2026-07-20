[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Testcode: Dummy-SecureString mit fiktivem Wert, um die Maskierung als <geheim> zu prüfen.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Testcode: Write-Host im Testblock stellt das reale Nutzungsszenario nach (Ausgabe in den Information-Stream).')]
param()

BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'InvokeWithEcho', 'InvokeWithEcho.psd1') -Force

    # Fängt die Write-Host-Ausgabe (Information-Stream) eines Aufrufs als Textzeilen ab.
    function Get-EchoOutput {
        param([scriptblock] $Call)
        (& $Call 6>&1) |
            Where-Object { $_ -is [System.Management.Automation.InformationRecord] } |
            ForEach-Object { "$_" }
    }
}

Describe 'Invoke-WithEcho' {

    It 'loggt den literalen Befehlstext mit >>-Präfix' {
        $lines = Get-EchoOutput { Invoke-WithEcho { Get-Date -Format yyyy } | Out-Null }
        $lines | Should -Contain '>> Get-Date -Format yyyy'
    }

    It 'reicht den Rückgabewert unverändert durch' {
        $x = Invoke-WithEcho { 1..3 | ForEach-Object { $_ * 2 } } 6> $null
        $x | Should -Be @(2, 4, 6)
    }

    It 'loggt Werte referenzierter Variablen als Zusatzzeile' {
        $pfad = 'C:\daten\import'
        $lines = Get-EchoOutput { Invoke-WithEcho { "$pfad" } | Out-Null }
        $lines | Should -Contain '   $pfad = C:\daten\import'
    }

    It 'kürzt Werte auf MaxValueLength Zeichen mit …-Suffix' {
        $lang = 'x' * 200
        $lines = Get-EchoOutput { Invoke-WithEcho { "$lang" } -MaxValueLength 10 | Out-Null }
        $lines | Should -Contain ('   $lang = ' + ('x' * 10) + '…')
    }

    It 'kürzt bei Default-Länge auf 100 Zeichen' {
        $lang = 'x' * 200
        $lines = Get-EchoOutput { Invoke-WithEcho { "$lang" } | Out-Null }
        $lines | Should -Contain ('   $lang = ' + ('x' * 100) + '…')
    }

    It 'formatiert Arrays mit Elementanzahl' {
        $dateien = 'a.csv', 'b.csv'
        $lines = Get-EchoOutput { Invoke-WithEcho { "$dateien" } | Out-Null }
        $lines | Should -Contain '   $dateien = (a.csv, b.csv)  [2 Elemente]'
    }

    It 'überspringt automatische Variablen wie $_' {
        $werte = 1, 2
        $lines = Get-EchoOutput { Invoke-WithEcho { $werte | ForEach-Object { $_ } } | Out-Null }
        (@($lines) -match '^\s+\$_ =') | Should -BeNullOrEmpty
    }

    It 'loggt blocklokale Variablen nicht (Zuweisung vor erster Lesung)' {
        $lines = Get-EchoOutput { Invoke-WithEcho { $a = 5; Write-Host $a } | Out-Null }
        (@($lines) -match '^\s+\$a =') | Should -BeNullOrEmpty
        $lines | Should -Contain '5'
    }

    It 'loggt Variablen, die vor der Zuweisung gelesen werden ($a = $a + 1)' {
        $a = 41
        $lines = Get-EchoOutput { Invoke-WithEcho { $a = $a + 1; $a } | Out-Null }
        $lines | Should -Contain '   $a = 41'
    }

    It 'loggt den Aufrufer-Wert bei zusammengesetzter Zuweisung (+=)' {
        $summe = 10
        $lines = Get-EchoOutput { Invoke-WithEcho { $summe += 1; $summe } | Out-Null }
        $lines | Should -Contain '   $summe = 10'
    }

    It 'loggt foreach-Laufvariablen nicht, wohl aber die durchlaufene Collection' {
        $dateien = 'a.csv', 'b.csv'
        $lines = Get-EchoOutput { Invoke-WithEcho { foreach ($f in $dateien) { $f } } | Out-Null }
        (@($lines) -match '^\s+\$f =') | Should -BeNullOrEmpty
        $lines | Should -Contain '   $dateien = (a.csv, b.csv)  [2 Elemente]'
    }

    It 'loggt nicht definierte Variablen als nicht-definiert-Platzhalter' {
        $lines = Get-EchoOutput { Invoke-WithEcho { "$gibtEsNicht" } | Out-Null }
        $lines | Should -Contain '   $gibtEsNicht = <nicht definiert / null>'
    }

    It 'maskiert SecureString-Werte' {
        $geheim = ConvertTo-SecureString 'hunter2' -AsPlainText -Force
        $lines = Get-EchoOutput { Invoke-WithEcho { "$geheim" } | Out-Null }
        $lines | Should -Contain '   $geheim = <geheim>'
    }

    It 'unterdrückt Wertezeilen mit -NoExpand' {
        $pfad = 'C:\daten'
        $lines = Get-EchoOutput { Invoke-WithEcho { "$pfad" } -NoExpand | Out-Null }
        (@($lines) -match '^\s{3}\$') | Should -BeNullOrEmpty
    }

    It 'loggt mehrzeilige Blöcke zeilenweise mit normalisierter Einrückung' {
        $lines = Get-EchoOutput {
            Invoke-WithEcho {
                $a = 1
                $a + 1
            } | Out-Null
        }
        $lines | Should -Contain '>> $a = 1'
        $lines | Should -Contain '>> $a + 1'
    }

    It 'hält Farbcodes aus dem Information-Stream-Text heraus' {
        $pfad = 'C:\daten'
        $farbig = Get-EchoOutput { Invoke-WithEcho { "$pfad" } | Out-Null }
        $ohne = Get-EchoOutput { Invoke-WithEcho { "$pfad" } -NoColor | Out-Null }
        $farbig | Should -Be $ohne
        (@($farbig) -match "`e") | Should -BeNullOrEmpty
    }

    It 'propagiert Fehler aus dem Block an den Aufrufer' {
        { Invoke-WithEcho { throw 'kaputt' } 6> $null } | Should -Throw 'kaputt'
    }
}
