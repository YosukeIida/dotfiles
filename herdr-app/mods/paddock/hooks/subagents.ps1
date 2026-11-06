# Paddock's subagent hook on Windows, where an agent runs hooks with cmd.exe and Git's
# sh isn't on PATH (Codex). Same as subagents.sh: puts each running subagent on the
# agent's own herdr-core terminal as a label, so the sidebar can list it.
#   SubagentStart  paddock.sub.<app>.<agent_id>={"app","type","at","s"}  (s: the session)
#   SubagentStop   removes it, a moment later (StopFailure too)
#   SessionStart   (startup or resume) removes every paddock.sub.<app>.* label left over
#   SessionEnd     removes this session's labels
# Registered with "async": true. It reads the hook's JSON from stdin and keeps only the
# event name, session, agent id and type; it opens no file except Codex's
# session_index.jsonl and uses no network. It prints nothing and always exits 0.
#
# Which terminal: HC_TERMINAL_ID when the agent runs its hooks itself. Codex usually
# runs them from its shared background server, started outside Herdr, so for Codex
# the hook finds its terminal: the live Codex terminal whose title holds the thread's
# name (from Codex's session_index.jsonl), else the only live Codex terminal in the
# session's folder. When that's ambiguous it does nothing.
param([string]$App = "claude")
$ErrorActionPreference = "SilentlyContinue"
# hc speaks UTF-8, and so does the hook's input; Windows' console code page may not.
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding $false } catch {}
# pwsh 7.3+ quotes native arguments itself: keep 5.1's behaviour, escaped by hand below.
$PSNativeCommandArgumentPassing = 'Legacy'

function Json($text) { try { return $text | ConvertFrom-Json } catch { return $null } }
function Norm([string]$p) { return ($p -replace '/', '\').TrimEnd('\').ToLowerInvariant() }

function Find-CodexTerminal($hc, $in) {
  $list = @((Json (& $hc ls --json 2>$null | Out-String)).terminals |
    Where-Object { $_.agent -eq "codex" -and $_.state -eq "live" })
  if (-not $list.Count) { return $null }
  $sid = [string]$in.session_id
  $codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }
  $index = Join-Path $codexHome "session_index.jsonl"
  $name = $null
  if ($sid -and (Test-Path $index)) {
    foreach ($line in [IO.File]::ReadAllLines($index, [Text.Encoding]::UTF8)) {
      if ($line.Contains($sid)) { $e = Json $line; if ($e.id -eq $sid -and $e.thread_name) { $name = [string]$e.thread_name } }
    }
  }
  if ($name) {
    $hits = @($list | Where-Object { ([string](Json (& $hc get $_.address --json 2>$null | Out-String)).title).Contains($name) })
    if ($hits.Count -eq 1) { return $hits[0].address }
    return $null
  }
  $cwd = Norm ([string]$in.cwd)
  $same = @($list | Where-Object { (Norm ([string]$_.cwd)) -eq $cwd })
  if ($cwd -and $same.Count -eq 1) { return $same[0].address }
  return $null
}

try {
  $app = ($App -creplace '[^a-z0-9-]', '')
  if ($app.Length -gt 16) { $app = $app.Substring(0, 16) }
  $hc = (Get-Command hc -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
  if (-not $app -or -not $hc) { exit 0 }

  $reader = New-Object IO.StreamReader([Console]::OpenStandardInput(), [Text.Encoding]::UTF8)
  $in = Json ($reader.ReadToEnd())
  if (-not $in) { exit 0 }

  $term = $env:HC_TERMINAL_ID
  if (-not $term -and $app -eq "codex") { $term = Find-CodexTerminal $hc $in }
  if (-not $term) { exit 0 }

  # Ids, types and sessions are plain words; anything else is dropped rather than quoted.
  $clip = { param($s, $n) if ($s.Length -gt $n) { $s.Substring(0, $n) } else { $s } }
  $id = & $clip ([string]$in.agent_id -creplace '[^A-Za-z0-9_-]', '') 64
  $type = & $clip ([string]$in.agent_type -creplace '[^A-Za-z0-9_:. -]', '') 48
  $sid = & $clip ([string]$in.session_id -creplace '[^A-Za-z0-9_-]', '') 64
  $key = "paddock.sub.$app.$id"
  $mine = { (Json (& $hc get $term --json 2>$null | Out-String)).labels.PSObject.Properties | Where-Object { $_.Name -clike "paddock.sub.$app.*" } }

  switch -CaseSensitive ([string]$in.hook_event_name) {
    "SubagentStart" {
      if ($id) {
        $at = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
        # A space would split the argument where it also holds quotes: JSON-escape it.
        $value = '{"app":"' + $app + '","type":"' + ($type -replace ' ', '\u0020') + '","at":' + $at + ',"s":"' + $sid + '"}'
        # Legacy native argument passing drops inner double quotes: escape them.
        & $hc label $term ("$key=" + ($value -replace '"', '\"')) *> $null
      }
    }
    { $_ -cin "SubagentStop", "StopFailure" } {
      if ($id) {
        # A Stop can arrive before a slow Start for a subagent that ends at once.
        Start-Sleep -Seconds 2
        & $hc label $term "$key=" *> $null
      }
    }
    "SessionStart" {
      if (@("startup", "resume", "") -ccontains [string]$in.source) {
        foreach ($p in (& $mine)) { & $hc label $term "$($p.Name)=" *> $null }
      }
    }
    "SessionEnd" {
      if ($sid) {
        foreach ($p in (& $mine)) { if ((Json $p.Value).s -ceq $sid) { & $hc label $term "$($p.Name)=" *> $null } }
      }
    }
  }
} catch {}
exit 0
