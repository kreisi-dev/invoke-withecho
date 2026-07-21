# InvokeWithEcho

[![CI](https://github.com/kreisi-dev/Invoke-WithEcho/actions/workflows/ci.yml/badge.svg)](https://github.com/kreisi-dev/Invoke-WithEcho/actions/workflows/ci.yml)
[![PowerShell Gallery](https://img.shields.io/powershellgallery/v/InvokeWithEcho.svg)](https://www.powershellgallery.com/packages/InvokeWithEcho)

ECHO ON for PowerShell: runs a script block and logs the command text **before** execution, together with type and current value of every variable the block reads. Combined with `Start-Transcript`, every piece of output in the log file can be attributed to the command that produced it — what DOS batch files always offered with `ECHO ON` and PowerShell does not.

## Installation

```powershell
Install-Module InvokeWithEcho          # PowerShellGet
Install-PSResource InvokeWithEcho     # or PSResourceGet
```

## Usage

```powershell
Import-Module InvokeWithEcho

$sourcePath = 'C:\data\import'
$files = Invoke-WithEcho { Get-ChildItem $sourcePath -Filter *.csv }
```

Output (also lands in the transcript via the information stream):

```
>> Get-ChildItem $sourcePath -Filter *.csv
   Variable     Type    Count  Value
   --------     ----    -----  -----
   $sourcePath  String      1  C:\data\import
```

## Parameters

| Parameter | Default | Meaning |
|---|---|---|
| `-ScriptBlock` | (mandatory, positional) | The block to execute. |
| `-MaxValueLength` | `100` | Maximum length per logged variable value; longer values end with `…`. |
| `-NoExpand` | off | Log only the command text, no variable values. |
| `-CommandColor` | `Cyan` | Console color of the `>>` command lines. |
| `-ValueColor` | `DarkGray` | Console color of the variable lines. |
| `-NoColor` | off | Write echo lines in the console's default color. |
| `-Retry` | off | Re-invoke the block on terminating errors, with exponential backoff. |
| `-RetryCount` | `5` | Retries after the first attempt (6 attempts in total). Implies `-Retry`. |
| `-RetryDelaySeconds` | `2` | Delay before the first retry. Implies `-Retry`. |
| `-RetryBackoffFactor` | `2` | Delay multiplier per retry; `1` keeps the delay fixed. Implies `-Retry`. |
| `-RetryMaxDelaySeconds` | `60` | Upper limit for the growing delay. Implies `-Retry`. |
| `-RetryNoticeColor` | `Yellow` | Console color of the `!!` retry notice lines. |

Colors affect console rendering only — the transcript and `6>` redirection receive plain text without color codes.

## Design decisions

### Return value: `$x = Invoke-WithEcho { … }`, not `Invoke-WithEcho { $x = … }`

Script blocks run in a **child scope** of the caller. An assignment inside the block (`Invoke-WithEcho { $x = 5 }`) therefore evaporates — `$x` is empty after the call. Instead, the wrapper passes the block's pipeline output through unchanged, so the assignment goes outside, as with `Measure-Command` or `Invoke-Command`:

```powershell
$x = Invoke-WithEcho { Get-ChildItem $sourcePath }   # correct
Invoke-WithEcho { $x = Get-ChildItem $sourcePath }   # wrong: $x does not exist afterwards
```

### Variable resolution: command stays literal, values as a table below

The command text is logged exactly as written; the values appear below it as an aligned table (Variable, Type, Count, Value). The code stays recognizable and long values cannot wreck the command line. Resolution uses the block's AST (`VariableExpressionAst`) and `$PSCmdlet.GetVariableValue()` — it only **reads** variables in the caller's scope and never executes anything (no subexpressions, no method calls, no double side effects).

Special cases:

- Only values **read** from the caller's scope are logged: block-local variables (`{ $a = 5; Write-Host $a }`) and `foreach` loop variables produce no value line. A variable read before assignment (`$a = $a + 1`, `$sum += 1`) shows the caller's value.
- Automatic variables (`$_`, `$null`, `$true`, `$args`, …) are skipped.
- Values are collapsed to a single line (newlines become spaces) and truncated at `-MaxValueLength`.
- Collections: `(a.csv, b.csv)` with the item count in the Count column; hashtables: `{k=v, …}`.
- Undefined variables: Type and Count show `-`, Value shows `<not defined / null>` — incidentally reveals typos.
- `SecureString`/`PSCredential`: `<masked>`.
- Property and index assignments (`$obj.Prop = 5`, `$arr[0] = 5`) count as a read of the variable — the object's value is logged.
- Increment/decrement (`$a++`) counts as a read; the pre-increment caller value is logged.

### Retry: terminating errors, buffered output, exponential backoff

`-Retry` (or any `Retry*` tuning parameter) re-invokes the block when it throws. Built for transient failures such as Exchange Online throttling:

```powershell
$mailboxes = Invoke-WithEcho -Retry { Get-EXOMailbox -ResultSize Unlimited }
```

Each failed attempt logs a `!!` notice to the information stream (so the transcript tells the whole story); after the last attempt the **original error record** is rethrown, so `catch [SpecificException]` at the call site keeps working.

```
>> Get-EXOMailbox -ResultSize Unlimited
!! Attempt 1/6 failed: … - retrying in 2s
!! Attempt 2/6 failed: … - retrying in 4s
```

- Only **terminating** errors trigger a retry — promote non-terminating ones with `-ErrorAction Stop` inside the block.
- The default is exponential backoff (2/4/8/16/32 s, capped at `-RetryMaxDelaySeconds`), the usual guidance for throttled endpoints. `-RetryBackoffFactor 1` gives a fixed cadence, e.g. `-RetryCount 10 -RetryDelaySeconds 5 -RetryBackoffFactor 1` for 10 retries every 5 seconds.
- While retrying, output is **buffered per attempt**: a failed attempt's partial output is discarded, and only the successful attempt's output reaches the pipeline (arriving only once the attempt completes). Without retry, output streams through as before.
- Filtering *which* errors are retried (`-RetryOn`) is deliberately deferred to a later version.

### Output target: `Write-Host` (information stream)

Visible in the console, captured by `Start-Transcript`, redirectable with `6>` (`6> echo.log`) or suppressible (`6> $null`) — and never pollutes the return value.

## Tests & demo

```powershell
Invoke-Pester tests/                     # 31 Pester tests
pwsh -NoProfile -File examples/demo.ps1  # demo including Start-Transcript
```
