# Invoke-WithEcho

`ECHO ON` für PowerShell: führt einen ScriptBlock aus und loggt **vorher** den Befehlstext samt den aktuellen Werten der referenzierten Variablen. In Kombination mit `Start-Transcript` lässt sich damit im Log-File jeder Output dem auslösenden Befehl zuordnen — das, was DOS-Batchdateien mit `ECHO ON` immer konnten und PowerShell nicht bietet.

```powershell
Import-Module ./InvokeWithEcho/InvokeWithEcho.psd1

$quellPfad = 'C:\daten\import'
$dateien = Invoke-WithEcho { Get-ChildItem $quellPfad -Filter *.csv }
```

Ausgabe (landet über den Information-Stream auch im Transcript):

```
>> Get-ChildItem $quellPfad -Filter *.csv
   [String] $quellPfad = C:\daten\import
```

## Parameter

| Parameter | Default | Bedeutung |
|---|---|---|
| `-ScriptBlock` | (Pflicht, positional) | Der auszuführende Block. |
| `-MaxValueLength` | `100` | Maximale Länge pro geloggtem Variablenwert; längere Werte enden mit `…`. |
| `-NoExpand` | aus | Nur den Befehlstext loggen, keine Variablenwerte. |
| `-CommandColor` | `Cyan` | Konsolenfarbe der `>>`-Befehlszeilen. |
| `-ValueColor` | `DarkGray` | Konsolenfarbe der Variablen-Zusatzzeilen. |
| `-NoColor` | aus | Echo-Zeilen in der Standardfarbe der Konsole ausgeben. |

Die Farben betreffen nur die Konsolen-Darstellung — im Transcript und bei `6>`-Umleitung steht reiner Text ohne Farbcodes.

## Design-Entscheidungen

### Rückgabewert: `$x = Invoke-WithEcho { … }`, nicht `Invoke-WithEcho { $x = … }`

ScriptBlocks laufen in einem **Child-Scope** des Aufrufers. Eine Zuweisung im Block (`Invoke-WithEcho { $x = 5 }`) verpufft daher — `$x` ist nach dem Aufruf leer. Der Wrapper reicht stattdessen die Pipeline-Ausgabe des Blocks unverändert durch, sodass die Zuweisung wie bei `Measure-Command` oder `Invoke-Command` außen steht:

```powershell
$x = Invoke-WithEcho { Get-ChildItem $quellPfad }   # richtig
Invoke-WithEcho { $x = Get-ChildItem $quellPfad }   # falsch: $x existiert danach nicht
```

### Variablenauflösung: Befehl bleibt original, Werte als Zusatzzeilen

Der Befehlstext wird 1:1 wie im Skript geloggt; die Werte stehen darunter. So bleibt der Code wiedererkennbar und lange Werte zerstören nicht die Befehlszeile. Die Auflösung geht über den AST des Blocks (`VariableExpressionAst`) und `$PSCmdlet.GetVariableValue()` — sie **liest nur** Variablen im Scope des Aufrufers und führt nichts aus (keine Subexpressions, keine Methodenaufrufe, keine doppelten Seiteneffekte).

Sonderfälle:

- Geloggt wird nur, was aus dem Aufrufer-Scope **gelesen** wird: blocklokale Variablen (`{ $a = 5; Write-Host $a }`) und `foreach`-Laufvariablen erzeugen keine Wertezeile. Wird eine Variable vor der Zuweisung gelesen (`$a = $a + 1`, `$summe += 1`), erscheint der Aufrufer-Wert.
- Automatische Variablen (`$_`, `$null`, `$true`, `$args`, …) werden übersprungen.
- Collections: `(a.csv, b.csv)  [2 Elemente]`, Hashtables: `{k=v, …}`.
- Nicht definierte Variablen: `<nicht definiert / null>` — deckt nebenbei Tippfehler auf.
- `SecureString`/`PSCredential`: `<geheim>`.

### Ausgabeziel: `Write-Host` (Information-Stream)

Sichtbar in der Konsole, wird von `Start-Transcript` erfasst, per `6>` umleitbar (`6> echo.log`) oder unterdrückbar (`6> $null`) — und verschmutzt nie den Rückgabewert.

## Tests & Demo

```powershell
Invoke-Pester tests/                     # 12 Pester-Tests
pwsh -NoProfile -File examples/demo.ps1  # Demo inkl. Start-Transcript
```
