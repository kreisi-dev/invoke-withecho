[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test code: dummy SecureString with a fictional value to verify masking as <masked>.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Test code: Write-Host inside the test block mirrors the real usage scenario (output to the information stream).')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '',
    Justification = 'Test code: a global variable is the test subject (scope-prefixed resolution); it is removed in the finally block.')]
param()

BeforeAll {
    # Single -ChildPath with separators: -AdditionalChildPath does not exist in PowerShell 5.1
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '../InvokeWithEcho/InvokeWithEcho.psd1') -Force

    # Captures the Write-Host output (information stream) of a call as text lines.
    function Get-EchoOutput {
        param([scriptblock] $Call)
        (& $Call 6>&1) |
            Where-Object { $_ -is [System.Management.Automation.InformationRecord] } |
            ForEach-Object { "$_" }
    }
}

Describe 'Invoke-WithEcho' {

    It 'logs the literal command text with a >> prefix' {
        $lines = Get-EchoOutput { Invoke-WithEcho { Get-Date -Format yyyy } | Out-Null }
        $lines | Should -Contain '>> Get-Date -Format yyyy'
    }

    It 'passes the return value through unchanged' {
        $x = Invoke-WithEcho { 1..3 | ForEach-Object { $_ * 2 } } 6> $null
        $x | Should -Be @(2, 4, 6)
    }

    It 'prints a table header above the variable rows' {
        $path = 'C:\data\import'
        $lines = Get-EchoOutput { Invoke-WithEcho { "$path" } | Out-Null }
        (@($lines) -match '^\s{3}Variable\s+Type\s+Count\s+Value$') | Should -Not -BeNullOrEmpty
    }

    It 'logs referenced variables as a table row with name, type, count, and value' {
        $path = 'C:\data\import'
        $lines = Get-EchoOutput { Invoke-WithEcho { "$path" } | Out-Null }
        (@($lines) -match '^\s{3}\$path\s+String\s+1\s+C:\\data\\import$') | Should -Not -BeNullOrEmpty
    }

    It 'truncates values at MaxValueLength characters with an … suffix' {
        $long = 'x' * 200
        $lines = Get-EchoOutput { Invoke-WithEcho { "$long" } -MaxValueLength 10 | Out-Null }
        (@($lines) -match ('\$long\s+String\s+1\s+' + ('x' * 10) + '…$')) | Should -Not -BeNullOrEmpty
    }

    It 'truncates at 100 characters by default' {
        $long = 'x' * 200
        $lines = Get-EchoOutput { Invoke-WithEcho { "$long" } | Out-Null }
        (@($lines) -match ('\$long\s+String\s+1\s+' + ('x' * 100) + '…$')) | Should -Not -BeNullOrEmpty
    }

    It 'formats arrays with their item count in the Count column' {
        $files = 'a.csv', 'b.csv'
        $lines = Get-EchoOutput { Invoke-WithEcho { "$files" } | Out-Null }
        (@($lines) -match '^\s{3}\$files\s+Object\[\]\s+2\s+\(a\.csv, b\.csv\)$') | Should -Not -BeNullOrEmpty
    }

    It 'collapses multi-line values to a single line' {
        $text = "line1`nline2"
        $lines = Get-EchoOutput { Invoke-WithEcho { "$text" } | Out-Null }
        (@($lines) -match '^\s{3}\$text\s+String\s+1\s+line1 line2$') | Should -Not -BeNullOrEmpty
    }

    It 'skips automatic variables such as $_' {
        $values = 1, 2
        $lines = Get-EchoOutput { Invoke-WithEcho { $values | ForEach-Object { $_ } } | Out-Null }
        (@($lines) -match '^\s{3}\$_\s') | Should -BeNullOrEmpty
    }

    It 'does not log block-local variables (assignment before first read)' {
        $lines = Get-EchoOutput { Invoke-WithEcho { $a = 5; Write-Host $a } | Out-Null }
        (@($lines) -match '^\s{3}') | Should -BeNullOrEmpty
        $lines | Should -Contain '5'
    }

    It 'logs variables read before assignment ($a = $a + 1)' {
        $a = 41
        $lines = Get-EchoOutput { Invoke-WithEcho { $a = $a + 1; $a } | Out-Null }
        (@($lines) -match '^\s{3}\$a\s+Int32\s+1\s+41$') | Should -Not -BeNullOrEmpty
    }

    It 'logs the caller value for compound assignment (+=)' {
        $sum = 10
        $lines = Get-EchoOutput { Invoke-WithEcho { $sum += 1; $sum } | Out-Null }
        (@($lines) -match '^\s{3}\$sum\s+Int32\s+1\s+10$') | Should -Not -BeNullOrEmpty
    }

    It 'does not log foreach loop variables, but does log the traversed collection' {
        $files = 'a.csv', 'b.csv'
        $lines = Get-EchoOutput { Invoke-WithEcho { foreach ($f in $files) { $f } } | Out-Null }
        (@($lines) -match '^\s{3}\$f\s') | Should -BeNullOrEmpty
        (@($lines) -match '^\s{3}\$files\s+Object\[\]\s+2\s+\(a\.csv, b\.csv\)$') | Should -Not -BeNullOrEmpty
    }

    It 'resolves scope-prefixed variables in the caller''s scope, not the module''s' {
        $script:scopedCfg = 'from-script-scope'
        $global:scopedGlobal = 'from-global-scope'
        try {
            $lines = Get-EchoOutput { Invoke-WithEcho { "$script:scopedCfg $global:scopedGlobal" } | Out-Null }
            (@($lines) -match '^\s{3}\$script:scopedCfg\s+String\s+1\s+from-script-scope$') | Should -Not -BeNullOrEmpty
            (@($lines) -match '^\s{3}\$global:scopedGlobal\s+String\s+1\s+from-global-scope$') | Should -Not -BeNullOrEmpty
        }
        finally {
            Remove-Variable -Name scopedGlobal -Scope Global -ErrorAction SilentlyContinue
            Remove-Variable -Name scopedCfg -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'logs undefined variables with dashes and a not-defined placeholder' {
        $lines = Get-EchoOutput { Invoke-WithEcho { "$doesNotExist" } | Out-Null }
        (@($lines) -match '^\s{3}\$doesNotExist\s+-\s+-\s+<not defined / null>$') | Should -Not -BeNullOrEmpty
    }

    It 'masks SecureString values' {
        $secret = ConvertTo-SecureString 'hunter2' -AsPlainText -Force
        $lines = Get-EchoOutput { Invoke-WithEcho { "$secret" } | Out-Null }
        (@($lines) -match '^\s{3}\$secret\s+SecureString\s+1\s+<masked>$') | Should -Not -BeNullOrEmpty
    }

    It 'suppresses the variable table with -NoExpand' {
        $path = 'C:\data'
        $lines = Get-EchoOutput { Invoke-WithEcho { "$path" } -NoExpand | Out-Null }
        (@($lines) -match '^\s{3}\S') | Should -BeNullOrEmpty
    }

    It 'logs multi-line blocks line by line with normalized indentation' {
        $lines = Get-EchoOutput {
            Invoke-WithEcho {
                $a = 1
                $a + 1
            } | Out-Null
        }
        $lines | Should -Contain '>> $a = 1'
        $lines | Should -Contain '>> $a + 1'
    }

    It 'keeps color codes out of the information stream text' {
        $path = 'C:\data'
        $colored = Get-EchoOutput { Invoke-WithEcho { "$path" } | Out-Null }
        $plain = Get-EchoOutput { Invoke-WithEcho { "$path" } -NoColor | Out-Null }
        $colored | Should -Be $plain
        (@($colored) -match '\x1b') | Should -BeNullOrEmpty
    }

    It 'propagates errors from the block to the caller' {
        { Invoke-WithEcho { throw 'broken' } 6> $null } | Should -Throw 'broken'
    }
}
