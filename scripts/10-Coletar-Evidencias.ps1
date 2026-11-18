#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ETAPA 6 - Junta os logs gerados na operação dentro de evidencias\ e cria um .zip para o GitHub.

.DESCRIPTION
    Copia para a pasta evidencias do repositório:
      05-monitoramento : alertas.log, recursos.csv, amostra do CSV do perfmon, eventos 9001 e 2031
      06-teste-falha   : recuperacao.log, saídas do Teste-Falha.ps1, eventos de serviço (7031/7034/7036)
      07-logs          : amostra dos eventos Security, log do IIS mais recente
    Depois lista os prints (.png) que ainda faltam e gera C:\Temp\evidencias-citizentech.zip.

    Como levar o .zip para o GitHub: veja docs\roteiro-configuracao.md, seção "Levar as evidências para o repositório".
#>
. "$PSScriptRoot\00-Config.ps1"
. "$PSScriptRoot\lib\Comum.ps1"

Write-Etapa 'Coleta das evidências'

function Copiar-SeExistir {
    param([string]$Origem, [string]$Destino)
    if (Test-Path $Origem) {
        Copy-Item -Path $Origem -Destination (Join-Path $PastaEvidencias $Destino) -Force
        Write-Ok "$Origem -> evidencias\$Destino"
    } else {
        Write-Aviso "Não encontrado: $Origem"
    }
}

# ---------------------------------------------------------------- monitoramento
Write-Passo 'Monitoramento'
Copiar-SeExistir (Join-Path $Config.PastaLogs 'alertas.log')  '05-monitoramento\alertas.log'
Copiar-SeExistir (Join-Path $Config.PastaLogs 'recursos.csv') '05-monitoramento\recursos.csv'

$csvPerf = Get-ChildItem $Config.PastaPerfLogs -Recurse -Filter *.csv -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($csvPerf) {
    Get-Content $csvPerf.FullName -TotalCount 60 |
        Set-Content (Join-Path $PastaEvidencias '05-monitoramento\perflogs-amostra.csv') -Encoding UTF8
    Write-Ok "Amostra de $($csvPerf.Name) -> evidencias\05-monitoramento\perflogs-amostra.csv"
}

Invoke-Evidencia -Titulo 'Eventos de alerta (Application 9001 e Diagnosis-PLA 2031)' -Arquivo '05-monitoramento\eventos-alerta.txt' -Comando {
    'Application / CitizenTechMonitor (9001):'
    Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'CitizenTechMonitor'; Id = 9001 } -MaxEvents 15 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated, Id, LevelDisplayName, Message -AutoSize -Wrap
    'Microsoft-Windows-Diagnosis-PLA/Operational (2031 = limite do alerta atingido):'
    Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnosis-PLA/Operational'; Id = 2031 } -MaxEvents 15 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated, Id, @{ n = 'Mensagem'; e = { ($_.Message -split "`r?`n")[0] } } -AutoSize -Wrap
}

# ---------------------------------------------------------------- teste de falha
Write-Passo 'Teste de falha e recuperação'
Copiar-SeExistir (Join-Path $Config.PastaLogs 'recuperacao.log') '06-teste-falha\recuperacao.log'
Get-ChildItem $Config.PastaLogs -Filter 'teste-falha-*.txt' -ErrorAction SilentlyContinue | ForEach-Object {
    Copiar-SeExistir $_.FullName "06-teste-falha\$($_.Name)"
}

Invoke-Evidencia -Titulo 'Eventos de serviço do IIS (7031/7034 queda inesperada, 7036 mudança de estado) e recuperação (9101)' -Arquivo '06-teste-falha\eventos-servico.txt' -Comando {
    $nomes = @((Get-Service W3SVC).DisplayName, (Get-Service WAS).DisplayName) | ForEach-Object { [regex]::Escape($_) }
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; ProviderName = 'Service Control Manager'; Id = 7031, 7034, 7036 } -MaxEvents 400 -ErrorAction SilentlyContinue |
        Where-Object { $_.Message -match ($nomes -join '|') } | Select-Object -First 25 |
        Format-Table TimeCreated, Id, @{ n = 'Mensagem'; e = { ($_.Message -split "`r?`n")[0] } } -AutoSize -Wrap
    Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'CitizenTechRecuperacao' } -MaxEvents 15 -ErrorAction SilentlyContinue |
        Format-Table TimeCreated, Id, LevelDisplayName, Message -AutoSize -Wrap
}

# ---------------------------------------------------------------- logs e auditoria
Write-Passo 'Logs e auditoria'
netsh http flush logbuffer | Out-Null
$logIIS = Get-ChildItem 'C:\inetpub\logs\LogFiles' -Recurse -Filter *.log -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($logIIS) {
    Get-Content $logIIS.FullName -Tail 200 | Set-Content (Join-Path $PastaEvidencias "07-logs\iis-$($logIIS.Name)") -Encoding UTF8
    Write-Ok "Últimas 200 linhas de $($logIIS.Name) -> evidencias\07-logs"
}
Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4624, 4625, 4663, 4720, 4728 } -MaxEvents 200 -ErrorAction SilentlyContinue |
    Select-Object TimeCreated, Id, @{ n = 'Resumo'; e = { ($_.Message -split "`r?`n")[0] } } |
    Export-Csv (Join-Path $PastaEvidencias '07-logs\eventos-security.csv') -NoTypeInformation -Encoding UTF8 -Delimiter ';'
Write-Ok 'Eventos 4624/4625/4663/4720/4728 -> evidencias\07-logs\eventos-security.csv'

# ---------------------------------------------------------------- prints que faltam
Write-Passo 'Conferência dos prints (.png)'
$printsEsperados = @(
    '01-rede\winver.png', '01-rede\ipconfig-all.png',
    '02-ad-dns\get-addomain.png', '02-ad-dns\nslookup.png', '02-ad-dns\get-dnsserverzone.png', '02-ad-dns\usuarios-grupos.png',
    '03-iis\get-windowsfeature-web.png', '03-iis\get-website.png', '03-iis\get-webapppoolstate.png',
    '03-iis\navegador-site.png', '03-iis\get-acl.png', '03-iis\aba-seguranca.png',
    '04-ntfs-gpo\get-smbshare.png', '04-ntfs-gpo\acesso-share-cliente.png', '04-ntfs-gpo\get-gpo-all.png',
    '04-ntfs-gpo\usuario-sem-painel.png', '04-ntfs-gpo\rdp-conexao.png', '04-ntfs-gpo\get-dfsnroot.png',
    '05-monitoramento\perfmon-conjunto-ativo.png', '05-monitoramento\perfmon-grafico.png',
    '05-monitoramento\monitor-recursos.png', '05-monitoramento\evento-alerta.png', '05-monitoramento\agendador-tarefas.png',
    '06-teste-falha\sc-qfailure.png', '06-teste-falha\services-recuperacao.png', '06-teste-falha\teste-falha-etapas.png',
    '06-teste-falha\navegador-voltou.png', '06-teste-falha\recuperacao-log.png',
    '07-logs\auditpol.png', '07-logs\eventviewer-security.png', '07-logs\iis-logs-pasta.png',
    '08-validacao-final\ficha-infraestrutura.png'
)
$faltando = $printsEsperados | Where-Object { -not (Test-Path (Join-Path $PastaEvidencias $_)) }
if ($faltando) {
    Write-Aviso "$($faltando.Count) de $($printsEsperados.Count) prints ainda não estão na pasta evidencias (normal se vocês tiram os prints no computador de vocês):"
    $faltando | ForEach-Object { Write-Host "     - evidencias\$_" }
} else {
    Write-Ok 'Todos os prints esperados estão na pasta evidencias.'
}

# ---------------------------------------------------------------- zip
Write-Passo 'Gerando o .zip'
New-Item -Path $Config.PastaTemp -ItemType Directory -Force | Out-Null
$zip = Join-Path $Config.PastaTemp 'evidencias-citizentech.zip'
Compress-Archive -Path $PastaEvidencias -DestinationPath $zip -Force
Write-Ok "Arquivo pronto: $zip"
Write-Host 'No seu computador, extraia o .zip na RAIZ do repositório (ele já contém a pasta evidencias) e faça o commit.' -ForegroundColor Green
