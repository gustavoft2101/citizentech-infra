<#
.SYNOPSIS
    Monitor-Recursos.ps1 (item 6.2 do roteiro) - Alerta por limiar de CPU, memória e disco.

.DESCRIPTION
    Instalado em C:\Scripts\Monitor-Recursos.ps1 pelo 07-Monitoramento.ps1 e executado
    a cada 5 minutos pela tarefa agendada CitizenTech_Monitor_Alertas (como SYSTEM).

    A cada execução:
      - mede CPU (média de 3 leituras), memória livre e espaço livre no C:
      - grava a leitura no histórico C:\Scripts\logs\recursos.csv
      - se algum valor passar do limite: grava em C:\Scripts\logs\alertas.log,
        registra o evento 9001 (Aviso) no log Application, origem CitizenTechMonitor,
        e mostra a linha em amarelo; senão mostra a linha verde com os três valores.

    As leituras usam CIM/WMI, que não depende do idioma do Windows.
    (O Get-Counter do roteiro exige o nome do contador no idioma instalado.)

.PARAMETER Simulacao
    Marca a execução como teste. Use junto com limites baixos para demonstrar o alerta
    sem precisar estressar o servidor. As linhas ficam marcadas com [SIMULACAO].

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Scripts\Monitor-Recursos.ps1

.EXAMPLE
    # Demonstração dos três alertas (limiares artificiais):
    C:\Scripts\Monitor-Recursos.ps1 -LimiteCPU -1 -LimiteRAM_MB 999999 -LimiteDisco_GB 99999 -Simulacao
#>
param(
    [double]$LimiteCPU      = 80,      # % de CPU
    [double]$LimiteRAM_MB   = 500,     # MB livres
    [double]$LimiteDisco_GB = 15,      # GB livres no C:
    [string]$PastaLogs      = 'C:\Scripts\logs',
    [switch]$Simulacao
)

$logAlertas   = Join-Path $PastaLogs 'alertas.log'
$csvHistorico = Join-Path $PastaLogs 'recursos.csv'
$origemEvento = 'CitizenTechMonitor'
New-Item -Path $PastaLogs -ItemType Directory -Force | Out-Null

# ---------------------------------------------------------------- leituras
# CPU: média de 3 leituras de 1 segundo (uma leitura só oscila muito)
$amostras = 1..3 | ForEach-Object {
    (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
    Start-Sleep -Seconds 1
}
$cpu = ($amostras | Measure-Object -Average).Average

# Memória: FreePhysicalMemory vem em KB -> dividir por 1024 dá MB
$so      = Get-CimInstance Win32_OperatingSystem
$ramLivre = $so.FreePhysicalMemory / 1024
$ramTotal = $so.TotalVisibleMemorySize / 1024

# Disco C:
$disco         = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
$discoLivreGB  = $disco.FreeSpace / 1GB
$discoLivrePct = ($disco.FreeSpace / $disco.Size) * 100

$agora = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# ---------------------------------------------------------------- histórico (acompanhamento)
if (-not (Test-Path $csvHistorico)) {
    Add-Content -Path $csvHistorico -Value 'DataHora;CPU_pct;RAM_livre_MB;RAM_total_MB;Disco_livre_GB;Disco_livre_pct;Alerta'
}

# ---------------------------------------------------------------- comparação com os limites
$alertas = @()
if ($cpu -gt $LimiteCPU)               { $alertas += "CPU alta: $([math]::Round($cpu,1))% (limite $LimiteCPU%)" }
if ($ramLivre -lt $LimiteRAM_MB)       { $alertas += "Memoria baixa: $([math]::Round($ramLivre,0)) MB livres (limite $LimiteRAM_MB MB)" }
if ($discoLivreGB -lt $LimiteDisco_GB) { $alertas += "Disco baixo: $([math]::Round($discoLivreGB,2)) GB livres (limite $LimiteDisco_GB GB)" }

$marca = ''
if ($Simulacao) { $marca = '[SIMULACAO] ' }

$linhaCsv = '{0};{1:N1};{2:N0};{3:N0};{4:N2};{5:N1};{6}' -f $agora, $cpu, $ramLivre, $ramTotal, $discoLivreGB, $discoLivrePct, ($alertas.Count -gt 0)
Add-Content -Path $csvHistorico -Value $linhaCsv

if ($alertas.Count -gt 0) {
    $mensagem = "$agora | $marca" + ($alertas -join ' | ')
    Add-Content -Path $logAlertas -Value $mensagem

    # Evento no Visualizador de Eventos (Application, ID 9001, Aviso)
    try {
        if (-not [System.Diagnostics.EventLog]::SourceExists($origemEvento)) {
            New-EventLog -LogName Application -Source $origemEvento
        }
        Write-EventLog -LogName Application -Source $origemEvento -EventId 9001 -EntryType Warning `
            -Message "AlertaEncosta / SRV-CITIZENTECH - $mensagem"
    } catch {
        Write-Host "Nao foi possivel gravar no Visualizador de Eventos: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host $mensagem -ForegroundColor Yellow
}
else {
    Write-Host ("{0} Recursos normais. CPU: {1:N1}% | RAM livre: {2:N0} MB | Disco livre: {3:N1} GB ({4:N0}%)" -f `
        (Get-Date -Format 'HH:mm:ss'), $cpu, $ramLivre, $discoLivreGB, $discoLivrePct) -ForegroundColor Green
}
