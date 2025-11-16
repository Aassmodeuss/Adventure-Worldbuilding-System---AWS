param(
  [string]$ApiKey = $env:OPENAI_API_KEY,
  [string]$ChatModel,
  [string]$ResponsesModel,
  [switch]$SkipChat,
  [switch]$SkipResponses
)

if (-not $ApiKey) { Write-Host 'OPENAI_API_KEY is not set.' -ForegroundColor Red; exit 1 }

function Invoke-OpenAIRequest {
  param([string]$Endpoint,[hashtable]$Body,[hashtable]$Headers)
  try {
    $resp = Invoke-RestMethod -Method Post -Uri $Endpoint -Headers $Headers -Body ($Body | ConvertTo-Json -Depth 8) -TimeoutSec 60
    return @{ ok=$true; data=$resp }
  } catch {
    $detail = $null
    try {
      if ($_.Exception.Response) {
        $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $detail = $sr.ReadToEnd(); $sr.Close()
      }
    } catch {}
    return @{ ok=$false; error=$_.Exception.Message; detail=$detail }
  }
}

$passCount = 0
$failCount = 0

if (-not $SkipChat) {
  $models = @()
  if ($ChatModel) { $models += $ChatModel } else { $models += 'gpt-4o'; $models += 'gpt-4o-mini' }
  foreach ($m in $models) {
    Write-Host "Chat smoketest with model '$m'..." -ForegroundColor Cyan
    $endpoint = 'https://api.openai.com/v1/chat/completions'
    $headers  = @{ Authorization = "Bearer $ApiKey"; 'Content-Type'='application/json' }
    $body = @{ model=$m; messages=@(@{role='user';content='Return exactly this JSON: {"ok": true}. No code fences, no extra text.'}); temperature=0.0 }
    $r = Invoke-OpenAIRequest -Endpoint $endpoint -Body $body -Headers $headers
    if ($r.ok) {
      $txt = $r.data.choices[0].message.content
      $isJson = $false
      try { $obj = $txt | ConvertFrom-Json; $isJson = ($obj.ok -eq $true) } catch {}
      if ($isJson) { Write-Host "PASS (Chat $m): {ok:true}" -ForegroundColor Green; $passCount++; break } else { Write-Host "FAIL (Chat $m): unexpected content`n$txt" -ForegroundColor Yellow; $failCount++ }
    } else {
      Write-Host "FAIL (Chat $m): $($r.error)" -ForegroundColor Yellow
      if ($r.detail) { Write-Host $r.detail -ForegroundColor DarkYellow }
      $failCount++
    }
  }
}

if (-not $SkipResponses) {
  $models = @()
  if ($ResponsesModel) { $models += $ResponsesModel } else { $models += 'gpt-4.1' }
  foreach ($m in $models) {
    Write-Host "Responses smoketest with model '$m'..." -ForegroundColor Cyan
    $endpoint = 'https://api.openai.com/v1/responses'
    $headers  = @{ Authorization = "Bearer $ApiKey"; 'Content-Type'='application/json'; 'OpenAI-Beta'='responses=v1' }
    $inputBlocks = @(
      @{ role='system'; content=@(@{ type='input_text'; text='You are a JSON-only function.' }) },
      @{ role='user';   content=@(@{ type='input_text'; text='Return exactly this JSON: {"ok": true}. No code fences.' }) }
    )
    $body = @{ model=$m; input=$inputBlocks; temperature=0.0; max_output_tokens=64 }
    $r = Invoke-OpenAIRequest -Endpoint $endpoint -Body $body -Headers $headers
    if ($r.ok) {
      $txt = $r.data.output_text
      if (-not $txt -and $r.data.output) {
        $parts = @()
        foreach ($blk in $r.data.output) { if ($blk.content) { foreach ($c in $blk.content) { if ($c.text) { $parts += $c.text } } } }
        $txt = ($parts -join "\n")
      }
      $isJson = $false
      try { $obj = $txt | ConvertFrom-Json; $isJson = ($obj.ok -eq $true) } catch {}
      if ($isJson) { Write-Host "PASS (Responses $m): {ok:true}" -ForegroundColor Green; $passCount++; break } else { Write-Host "FAIL (Responses $m): unexpected content`n$txt" -ForegroundColor Yellow; $failCount++ }
    } else {
      Write-Host "FAIL (Responses $m): $($r.error)" -ForegroundColor Yellow
      if ($r.detail) { Write-Host $r.detail -ForegroundColor DarkYellow }
      $failCount++
    }
  }
}

Write-Host "Smoketest summary: PASS=$passCount FAIL=$failCount" -ForegroundColor Magenta
if ($passCount -gt 0) { exit 0 } else { exit 1 }
