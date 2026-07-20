[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Test code: dummy SecureString with a fictional value to verify masking as <masked>.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'Test code: Write-Host inside the test block mirrors the real usage scenario (output to the information stream).')]
param()

BeforeAll {
    Import-Module (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'InvokeWithEcho', 'InvokeWithEcho.psd1') -Force

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

    It 'logs type and value of referenced variables as an extra line' {
        $path = 'C:\data\import'
        $lines = Get-EchoOutput { Invoke-WithEcho { "$path" } | Out-Null }
        $lines | Should -Contain '   [String] $path = C:\data\import'
    }

    It 'truncates values at MaxValueLength characters with an … suffix' {
        $long = 'x' * 200
        $lines = Get-EchoOutput { Invoke-WithEcho { "$long" } -MaxValueLength 10 | Out-Null }
        $lines | Should -Contain ('   [String] $long = ' + ('x' * 10) + '…')
    }

    It 'truncates at 100 characters by default' {
        $long = 'x' * 200
        $lines = Get-EchoOutput { Invoke-WithEcho { "$long" } | Out-Null }
        $lines | Should -Contain ('   [String] $long = ' + ('x' * 100) + '…')
    }

    It 'formats arrays with their item count' {
        $files = 'a.csv', 'b.csv'
        $lines = Get-EchoOutput { Invoke-WithEcho { "$files" } | Out-Null }
        $lines | Should -Contain '   [Object[]] $files = (a.csv, b.csv)  [2 items]'
    }

    It 'skips automatic variables such as $_' {
        $values = 1, 2
        $lines = Get-EchoOutput { Invoke-WithEcho { $values | ForEach-Object { $_ } } | Out-Null }
        (@($lines) -match '\$_ =') | Should -BeNullOrEmpty
    }

    It 'does not log block-local variables (assignment before first read)' {
        $lines = Get-EchoOutput { Invoke-WithEcho { $a = 5; Write-Host $a } | Out-Null }
        (@($lines) -match '^\s{3}.*\$a =') | Should -BeNullOrEmpty
        $lines | Should -Contain '5'
    }

    It 'logs variables read before assignment ($a = $a + 1)' {
        $a = 41
        $lines = Get-EchoOutput { Invoke-WithEcho { $a = $a + 1; $a } | Out-Null }
        $lines | Should -Contain '   [Int32] $a = 41'
    }

    It 'logs the caller value for compound assignment (+=)' {
        $sum = 10
        $lines = Get-EchoOutput { Invoke-WithEcho { $sum += 1; $sum } | Out-Null }
        $lines | Should -Contain '   [Int32] $sum = 10'
    }

    It 'does not log foreach loop variables, but does log the traversed collection' {
        $files = 'a.csv', 'b.csv'
        $lines = Get-EchoOutput { Invoke-WithEcho { foreach ($f in $files) { $f } } | Out-Null }
        (@($lines) -match '\$f =') | Should -BeNullOrEmpty
        $lines | Should -Contain '   [Object[]] $files = (a.csv, b.csv)  [2 items]'
    }

    It 'logs undefined variables with a not-defined placeholder' {
        $lines = Get-EchoOutput { Invoke-WithEcho { "$doesNotExist" } | Out-Null }
        $lines | Should -Contain '   $doesNotExist = <not defined / null>'
        (@($lines) -match '\[\w+\] \$doesNotExist') | Should -BeNullOrEmpty
    }

    It 'masks SecureString values' {
        $secret = ConvertTo-SecureString 'hunter2' -AsPlainText -Force
        $lines = Get-EchoOutput { Invoke-WithEcho { "$secret" } | Out-Null }
        $lines | Should -Contain '   [SecureString] $secret = <masked>'
    }

    It 'suppresses value lines with -NoExpand' {
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
        (@($colored) -match "`e") | Should -BeNullOrEmpty
    }

    It 'propagates errors from the block to the caller' {
        { Invoke-WithEcho { throw 'broken' } 6> $null } | Should -Throw 'broken'
    }
}
