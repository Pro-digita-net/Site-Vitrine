# Test local de l'image Docker du site vitrine (Docker Desktop requis).
# Usage (depuis la racine du projet) :
#   powershell -ExecutionPolicy Bypass -File .\scripts\test-docker.ps1
# Resultat detaille dans docker-test.log (ignore par git).

$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root
$log = Join-Path $root 'docker-test.log'
Set-Content -Path $log -Value "Test Docker Site-Vitrine - $(Get-Date -Format s)" -Encoding UTF8

$port = 8089
$env:LOCAL_PORT = "$port"
$base = "http://127.0.0.1:$port"
$compose = 'docker compose -p sv-test -f docker-compose.yml -f docker-compose.local.yml'
$script:fails = 0

function Log($m) { Write-Host $m; Add-Content -Path $log -Value $m -Encoding UTF8 }
function Run($cmd) {
  Log "> $cmd"
  $out = cmd /c "$cmd 2>&1"
  $code = $LASTEXITCODE
  $out | ForEach-Object { Log "    $_" }
  return $code
}
function Check($name, $ok) {
  if ($ok) { Log "PASS  $name" } else { Log "FAIL  $name"; $script:fails++ }
}
function Head($path, $extra = '') {
  $h = cmd /c "curl.exe -s -o NUL -D - $extra `"$base$path`" 2>&1" | Out-String
  Add-Content -Path $log -Value "--- HEAD $path`n$h" -Encoding UTF8
  return $h
}
function Status($h) { if ($h -match '^HTTP/\S+ (\d{3})') { return [int]$Matches[1] } return 0 }

Log '=== Build'
Check 'docker compose build' ((Run "$compose build --pull") -eq 0)

Log '=== Demarrage'
Check 'docker compose up' ((Run "$compose up -d") -eq 0)
$id = (cmd /c "$compose ps -q site 2>NUL" | Out-String).Trim()
Log "conteneur: $id"

$health = ''
for ($i = 0; $i -lt 30; $i++) {
  $health = (cmd /c "docker inspect -f {{.State.Health.Status}} $id 2>&1" | Out-String).Trim()
  if ($health -eq 'healthy') { break }
  Start-Sleep -Seconds 2
}
Check "healthcheck Docker = healthy (obtenu: $health)" ($health -eq 'healthy')

Log '=== HTTP'
$h = Head '/healthz'
Check '/healthz -> 200' ((Status $h) -eq 200)

$h = Head '/'
Check '/ -> 200' ((Status $h) -eq 200)
Check '/ Cache-Control no-cache' ($h -match '(?im)^Cache-Control:\s*no-cache')
Check '/ Content-Security-Policy' ($h -match '(?im)^Content-Security-Policy:')
Check '/ Strict-Transport-Security' ($h -match '(?im)^Strict-Transport-Security:')
Check '/ X-Content-Type-Options nosniff' ($h -match '(?im)^X-Content-Type-Options:\s*nosniff')
Check '/ version nginx masquee' (-not ($h -match '(?im)^Server:\s*nginx/\d'))

$html = cmd /c "curl.exe -s $base/" | Out-String
$js = if ($html -match '(/assets/index-[^"]+\.js)') { $Matches[1] } else { '' }
$css = if ($html -match '(/assets/index-[^"]+\.css)') { $Matches[1] } else { '' }
Check "index.html reference le bundle JS ($js)" ($js -ne '')
$h = Head $js '-H "Accept-Encoding: gzip"'
Check 'bundle JS -> 200' ((Status $h) -eq 200)
Check 'bundle JS compresse gzip' ($h -match '(?im)^Content-Encoding:\s*gzip')
Check 'bundle JS cache immutable' ($h -match '(?im)^Cache-Control:.*immutable')
Check 'bundle JS en-tetes securite' ($h -match '(?im)^X-Content-Type-Options:\s*nosniff')
$h = Head $css
Check "feuille CSS -> 200 ($css)" ((Status $h) -eq 200)

$h = Head '/assets/outfit.ttf'
Check 'police TTF -> 200 + font/ttf' (((Status $h) -eq 200) -and ($h -match '(?im)^Content-Type:\s*font/ttf'))
$h = Head '/assets/reference/hero-floor.webp'
Check 'image -> 200 + cache 7 jours' (((Status $h) -eq 200) -and ($h -match '(?im)^Cache-Control:.*max-age=604800'))
$h = Head '/assets/reference/architecture-screen-hd.svg' '-H "Accept-Encoding: gzip"'
Check 'SVG HD compresse gzip' ($h -match '(?im)^Content-Encoding:\s*gzip')
$h = Head '/favicon.svg'
Check '/favicon.svg -> 200' ((Status $h) -eq 200)
$h = Head '/assets/inexistant.webp'
Check 'asset manquant -> 404' ((Status $h) -eq 404)
$h = Head '/.env'
Check '/.env -> 404' ((Status $h) -eq 404)
$h = Head '/.git/config'
Check '/.git/config -> 404' ((Status $h) -eq 404)
$h = Head '/une/page/inconnue'
Check 'chemin inconnu -> index.html (200)' ((Status $h) -eq 200)

Log '=== Securite du conteneur'
$uid = (cmd /c "docker exec $id id -u 2>&1" | Out-String).Trim()
Check "utilisateur non-root (uid=$uid)" ($uid -eq '101')
cmd /c "docker exec $id touch /usr/share/nginx/html/x >NUL 2>&1"
Check 'fichiers du site non modifiables' ($LASTEXITCODE -ne 0)
cmd /c "docker exec $id touch /etc/nginx/x >NUL 2>&1"
Check 'systeme de fichiers en lecture seule' ($LASTEXITCODE -ne 0)
cmd /c "docker exec $id touch /tmp/x >NUL 2>&1"
Check '/tmp inscriptible (tmpfs)' ($LASTEXITCODE -eq 0)

Log '=== Journaux du conteneur'
Run "$compose logs --no-color site" | Out-Null

Log '=== Nettoyage'
Run "$compose down --rmi local" | Out-Null

Log ''
if ($script:fails -eq 0) { Log 'RESULTAT: TOUS LES TESTS SONT PASSES' } else { Log "RESULTAT: $($script:fails) TEST(S) EN ECHEC" }
exit $script:fails
