function Format-EchoValue {
    param($Value, [int] $MaxLength)

    if ($null -eq $Value) { return '<not defined / null>' }
    if ($Value -is [securestring] -or $Value -is [pscredential]) { return '<masked>' }

    if ($Value -is [System.Collections.IDictionary]) {
        $pairs = $Value.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
        $text = '{' + ($pairs -join ', ') + '}'
    }
    elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $text = '(' + (@($Value) -join ', ') + ')'
    }
    else {
        $text = "$Value"
    }

    $text = $text -replace '\r?\n', ' '   # keep the table row on a single line
    if ($text.Length -gt $MaxLength) { $text = $text.Substring(0, $MaxLength) + '…' }
    return $text
}
