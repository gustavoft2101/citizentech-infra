#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Teste-Falha.ps1 (item 7.2 do roteiro) - Derruba o site de propósito e prova que ele volta sozinho.

.DESCRIPTION
    Segue as 5 etapas do roteiro:
      [1] Estado antes     [2] Provoca a falha     [3] Tenta acessar durante a falha
      [4] Aguarda a recuperação AUTOMÁTICA          [5] Estado depois

    Três cenários (parâmetro -Cenario):
      Servico (padrão, igual ao roteiro): Stop-Service W3SVC.
          Uma parada "educada" não aciona a recuperação do Windows (ela só age
          quando o serviço cai sozinho). Quem religa é a tarefa agendada
          CitizenTech_Recuperacao (Recupera-Site.ps1), que roda a cada 1 minuto.
          Volta em até ~1 minuto e deixa registro no recuperacao.log.
      Crash: encerra à força o processo do W3SVC, simulando um travamento.
          Quem religa é o Gerenciador de Serviços do Windows, pela aba
          Recuperação configurada com sc.exe failure (5 s). Volta em segundos.
      Pool: para o pool CitizenTechPool (o site responde 503).
          Quem religa é a tarefa CitizenTech_Recuperacao.

    Tudo que aparece na tela fica gravado em C:\Scripts\logs\teste-falha-<cenario>-<data>.txt

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Scripts\Teste-Falha.ps1
    powershell -ExecutionPolicy Bypass -File C:\Scripts\Teste-Falha.ps1 -Cenario Crash
    powershell -ExecutionPolicy Bypass -File C:\Scripts\Teste-Falha.ps1 -Cenario Pool
#>
param(
    [ValidateSet('Servico', 'Crash', 'Pool')]
    [string]$Cenario     = 'Servico',
    [string]$Url         = 'http://localhost',
    [string]$Pool        = 'CitizenTechPool',
    [int]$TempoMaximoSeg = 150,
    [string]$PastaLogs   = 'C:\Scripts\logs'
)

Import-Module WebAdministration
New-Item -Path $PastaLogs -ItemType Directory -Force | Out-Null
$arquivoSaida = Join-Path $PastaLogs ('teste-falha-{0}-{1}.txt' -f $Cenario.ToLower(), (Get-Date -Format 'yyyyMMdd-HHmmss'))
Start-Transcript -Path $arquivoSaida | Out-Null

function Testar-Site {
    # Devolve o código HTTP (200, 503...) ou 0 quando não há resposta nenhuma.
    try {
        $resposta = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
        return [pscustomobject]@{ Codigo = [int]$resposta.StatusCode; Detalhe = $resposta.StatusDescription }
    } catch {
        $codigo = 0
        if ($_.Exception.Response) { $codigo = [int]$_.Exception.Response.StatusCode }
        return [pscustomobject]@{ Codigo = $codigo; Detalhe = $_.Exception.Message }
    }
}

function Mostrar-Estado {
    Get-Service W3SVC, WAS | Format-Table Name, Status, StartType -AutoSize | Out-Host
    try   { $estadoPool = (Get-WebAppPoolState -Name $Pool).Value } catch { $estadoPool = 'indisponivel' }
    $site = Testar-Site
    Write-Host "   Pool $Pool : $estadoPool"
    if ($site.Codigo -eq 200) { Write-Host "   Site $Url : HTTP $($site.Codigo) $($site.Detalhe)" -ForegroundColor Green }
    else                      { Write-Host "   Site $Url : FORA DO AR (HTTP $($site.Codigo)) $($site.Detalhe)" -ForegroundColor Red }
    return $site
}

$quemRecupera = @{
    Servico = 'tarefa agendada CitizenTech_Recuperacao (Recupera-Site.ps1, a cada 1 min)'
    Crash   = 'Gerenciador de Serviços do Windows (sc.exe failure: reinicia o W3SVC em 5 s)'
    Pool    = 'tarefa agendada CitizenTech_Recuperacao (Recupera-Site.ps1, a cada 1 min)'
}

Write-Host "=== TESTE DE FALHA - CITIZENTECH / ALERTAENCOSTA ===" -ForegroundColor Cyan
Write-Host "Cenário: $Cenario | Servidor: $env:COMPUTERNAME | Início: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')" -ForegroundColor Cyan

# ---------------------------------------------------------------- [1]
Write-Host "`n[1] Estado antes:" -ForegroundColor Yellow
$antes = Mostrar-Estado
if ($antes.Codigo -ne 200) {
    Write-Host 'O site já está fora do ar antes do teste. Corrija isso primeiro (rode C:\Scripts\Recupera-Site.ps1).' -ForegroundColor Red
    Stop-Transcript | Out-Null
    return
}

# ---------------------------------------------------------------- [2]
$inicioFalha = Get-Date
switch ($Cenario) {
    'Servico' {
        Write-Host "`n[2] Derrubando o serviço W3SVC (Stop-Service)..." -ForegroundColor Yellow
        Stop-Service W3SVC -Force
    }
    'Crash' {
        Write-Host "`n[2] Simulando TRAVAMENTO: encerrando à força o processo do W3SVC..." -ForegroundColor Yellow
        $idProcesso = (Get-CimInstance Win32_Service -Filter "Name='W3SVC'").ProcessId
        $noMesmoProcesso = Get-CimInstance Win32_Service -Filter "ProcessId=$idProcesso" | Select-Object -ExpandProperty Name
        Write-Host "   Processo svchost PID $idProcesso hospeda: $($noMesmoProcesso -join ', ')"
        $permitidos = @('W3SVC', 'WAS', 'W3LOGSVC', 'IISADMIN', 'AppHostSvc')
        $outros = $noMesmoProcesso | Where-Object { $permitidos -notcontains $_ }
        if ($outros) {
            Write-Host "   Cancelado por segurança: o processo também hospeda $($outros -join ', '). Use -Cenario Servico." -ForegroundColor Red
            Stop-Transcript | Out-Null
            return
        }
        Stop-Process -Id $idProcesso -Force
    }
    'Pool' {
        Write-Host "`n[2] Parando o pool de aplicativos $Pool..." -ForegroundColor Yellow
        Stop-WebAppPool -Name $Pool
    }
}
Start-Sleep -Seconds 1
Get-Service W3SVC, WAS | Format-Table Name, Status -AutoSize | Out-Host
try { Write-Host "   Pool $Pool : $((Get-WebAppPoolState -Name $Pool).Value)" } catch { Write-Host "   Pool $Pool : indisponivel" }

# ---------------------------------------------------------------- [3]
Write-Host "`n[3] Tentando acessar o site durante a falha..." -ForegroundColor Yellow
$durante = Testar-Site
if ($durante.Codigo -eq 200) {
    Write-Host '   O site ainda respondeu (a recuperação foi mais rápida que o teste).' -ForegroundColor Magenta
} else {
    Write-Host "   Site indisponível, como esperado: HTTP $($durante.Codigo) - $($durante.Detalhe)" -ForegroundColor Red
}

# ---------------------------------------------------------------- [4]
Write-Host "`n[4] Aguardando recuperação automática (até $TempoMaximoSeg s)..." -ForegroundColor Yellow
Write-Host "   Responsável: $($quemRecupera[$Cenario])"
$recuperou = $false
while (((Get-Date) - $inicioFalha).TotalSeconds -lt $TempoMaximoSeg) {
    Start-Sleep -Seconds 5
    $agora = Testar-Site
    $segundos = [int]((Get-Date) - $inicioFalha).TotalSeconds
    if ($agora.Codigo -eq 200) {
        Write-Host "   ${segundos}s: site respondeu HTTP 200." -ForegroundColor Green
        $recuperou = $true
        break
    }
    Write-Host "   ${segundos}s: ainda fora do ar (HTTP $($agora.Codigo))"
}

# ---------------------------------------------------------------- [5]
Write-Host "`n[5] Estado depois:" -ForegroundColor Yellow
$depois = Mostrar-Estado
$tempoTotal = [int]((Get-Date) - $inicioFalha).TotalSeconds

if ($recuperou) {
    Write-Host "`nRESULTADO: recuperação AUTOMÁTICA em $tempoTotal segundos, sem intervenção manual." -ForegroundColor Green
} else {
    Write-Host "`nRESULTADO: o site NÃO voltou sozinho em $TempoMaximoSeg s." -ForegroundColor Red
    Write-Host 'Confira: Get-ScheduledTask CitizenTech_Recuperacao | Get-ScheduledTaskInfo  e  sc.exe qfailure W3SVC' -ForegroundColor Red
    Write-Host 'Religando manualmente para não deixar o servidor fora do ar...' -ForegroundColor Red
    Start-Service WAS, W3SVC -ErrorAction SilentlyContinue
    Start-WebAppPool -Name $Pool -ErrorAction SilentlyContinue
}

Write-Host "`nEventos do Gerenciador de Serviços desde o início do teste (7031/7034 = queda inesperada, 7036 = mudança de estado):" -ForegroundColor Cyan
$nomeExibicao = (Get-Service W3SVC).DisplayName
Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; Id = 7031, 7034, 7036; StartTime = $inicioFalha.AddSeconds(-5) } -ErrorAction SilentlyContinue |
    Where-Object { $_.Message -match [regex]::Escape($nomeExibicao) -or $_.Message -match 'Windows Process Activation|Ativa..o de Processos' } |
    Sort-Object TimeCreated |
    Format-Table TimeCreated, Id, @{ n = 'Mensagem'; e = { ($_.Message -split "`r?`n")[0] } } -AutoSize -Wrap | Out-Host

$logRecuperacao = Join-Path $PastaLogs 'recuperacao.log'
if (Test-Path $logRecuperacao) {
    Write-Host "Últimas linhas de $logRecuperacao :" -ForegroundColor Cyan
    Get-Content $logRecuperacao -Tail 8 | Out-Host
}

Stop-Transcript | Out-Null
Write-Host "`nSaída completa salva em $arquivoSaida" -ForegroundColor DarkGray
