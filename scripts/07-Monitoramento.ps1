#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ETAPA 4 (itens 6.1, 6.2 e 6.3 do roteiro) - Monitor de Desempenho com alertas de CPU, memória e disco.

.DESCRIPTION
    6.1  Cria dois Conjuntos de Coletores de Dados no Monitor de Desempenho (perfmon):
           CitizenTech_Monitor  -> grava CPU, memória e disco a cada 15 s em C:\PerfLogs\CitizenTech (CSV)
           CitizenTech_Alertas  -> ALERTA nativo do perfmon: CPU > 80%, RAM livre < 500 MB,
                                   disco livre < 15%; cada disparo vira o evento 2031 no log
                                   Microsoft-Windows-Diagnosis-PLA/Operational
         Os dois são criados com o logman (ferramenta oficial do perfmon por linha de comando)
         e com os nomes dos contadores no idioma do Windows (Get-ContadorLocal).
    6.2  Instala o C:\Scripts\Monitor-Recursos.ps1 (alerta por limiar + evento 9001)
    6.3  Agenda o Monitor-Recursos.ps1 a cada 5 minutos e garante que os coletores
         voltem a rodar depois de um reinício. Liga o histórico do Agendador de Tarefas.
#>
. "$PSScriptRoot\00-Config.ps1"
. "$PSScriptRoot\lib\Comum.ps1"

Write-Etapa 'ETAPA 4 - Monitoramento com alertas'

New-Item -Path $Config.PastaPerfLogs, $Config.PastaScripts, $Config.PastaLogs -ItemType Directory -Force | Out-Null

# ---------------------------------------------------------------- contadores no idioma local
Write-Passo 'Nomes dos contadores no idioma deste Windows'
$cCPU   = Get-ContadorLocal '\Processor(_Total)\% Processor Time'
$cRAM   = Get-ContadorLocal '\Memory\Available MBytes'
$cDisco = Get-ContadorLocal '\LogicalDisk(C:)\% Free Space'
Invoke-Evidencia -Titulo 'Contadores monitorados' -Arquivo '05-monitoramento\contadores.txt' -Comando {
    [pscustomobject]@{ Recurso = 'CPU';     Contador = $cCPU;   Alerta = "> $($Config.LimiteCPU) %" }
    [pscustomobject]@{ Recurso = 'Memória'; Contador = $cRAM;   Alerta = "< $($Config.LimiteRAM_MB) MB livres" }
    [pscustomobject]@{ Recurso = 'Disco';   Contador = $cDisco; Alerta = "< $($Config.LimiteDiscoPct) % livre" }
}

# ---------------------------------------------------------------- 6.1 Data Collector Set de contadores
Write-Passo '6.1 Conjunto de coletores CitizenTech_Monitor (gravação dos contadores)'
logman stop   CitizenTech_Monitor 2>$null | Out-Null
logman delete CitizenTech_Monitor 2>$null | Out-Null
logman create counter CitizenTech_Monitor -c $cCPU $cRAM $cDisco `
    -si $Config.IntervaloColetaSeg -f csv -v mmddhhmm `
    -o (Join-Path $Config.PastaPerfLogs 'Recursos')
logman start CitizenTech_Monitor

# ---------------------------------------------------------------- 6.1 Alerta nativo do perfmon
Write-Passo '6.1 Conjunto de coletores CitizenTech_Alertas (alerta por limiar no Monitor de Desempenho)'
logman stop   CitizenTech_Alertas 2>$null | Out-Null
logman delete CitizenTech_Alertas 2>$null | Out-Null
logman create alert CitizenTech_Alertas `
    -th "$cCPU>$($Config.LimiteCPU)" "$cRAM<$($Config.LimiteRAM_MB)" "$cDisco<$($Config.LimiteDiscoPct)" `
    -si $Config.IntervaloColetaSeg -el
logman start CitizenTech_Alertas

Invoke-Evidencia -Titulo 'logman query (conjuntos de coletores)' -Arquivo '05-monitoramento\logman-query.txt' -Comando {
    logman query CitizenTech_Monitor
    logman query CitizenTech_Alertas
}

Start-Sleep -Seconds 5
Invoke-Evidencia -Titulo 'Get-Counter - leitura ao vivo dos três contadores' -Arquivo '05-monitoramento\get-counter.txt' -Comando {
    Get-Counter -Counter $cCPU, $cRAM, $cDisco -SampleInterval 2 -MaxSamples 3 |
        ForEach-Object { $_.CounterSamples } |
        Format-Table Timestamp, Path, @{ n = 'Valor'; e = { [math]::Round($_.CookedValue, 2) } } -AutoSize
    Get-ChildItem $Config.PastaPerfLogs -Recurse | Select-Object FullName, Length, LastWriteTime | Format-Table -AutoSize
}

# ---------------------------------------------------------------- 6.2 Script de alerta
Write-Passo '6.2 Script de alerta por limiar (Monitor-Recursos.ps1)'
if (-not [System.Diagnostics.EventLog]::SourceExists('CitizenTechMonitor')) {
    New-EventLog -LogName Application -Source 'CitizenTechMonitor'
}
Copy-Item "$PSScriptRoot\Monitor-Recursos.ps1", "$PSScriptRoot\Gerar-Carga.ps1" -Destination $Config.PastaScripts -Force
Get-ChildItem $Config.PastaScripts -Filter *.ps1 | Unblock-File
$monitor = Join-Path $Config.PastaScripts 'Monitor-Recursos.ps1'
Write-Ok "Instalado em $monitor"

Invoke-Evidencia -Titulo 'Execução do Monitor-Recursos.ps1 (limiares reais)' -Arquivo '05-monitoramento\monitor-recursos-execucao.txt' -Comando {
    & $monitor -LimiteCPU $Config.LimiteCPU -LimiteRAM_MB $Config.LimiteRAM_MB -LimiteDisco_GB $Config.LimiteDisco_GB
}

Invoke-Evidencia -Titulo 'Demonstração do alerta com limiares artificiais [SIMULACAO]' -Arquivo '05-monitoramento\monitor-recursos-simulacao.txt' -Comando {
    & $monitor -LimiteCPU -1 -LimiteRAM_MB 999999 -LimiteDisco_GB 99999 -Simulacao
    Start-Sleep -Seconds 1
    Get-WinEvent -FilterHashtable @{ LogName = 'Application'; ProviderName = 'CitizenTechMonitor'; Id = 9001 } -MaxEvents 3 |
        Format-Table TimeCreated, Id, LevelDisplayName, Message -AutoSize -Wrap
}

# ---------------------------------------------------------------- 6.3 Agendamentos
Write-Passo '6.3 Tarefas agendadas'
# Histórico do Agendador de Tarefas vem desligado no Windows Server; o print pede o histórico.
wevtutil set-log Microsoft-Windows-TaskScheduler/Operational /enabled:true

$argumentos = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$monitor`" " +
              "-LimiteCPU $($Config.LimiteCPU) -LimiteRAM_MB $($Config.LimiteRAM_MB) -LimiteDisco_GB $($Config.LimiteDisco_GB)"
$acao    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argumentos
$gatilho = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
               -RepetitionInterval (New-TimeSpan -Minutes $Config.IntervaloMonitorMin) `
               -RepetitionDuration (New-TimeSpan -Days 3650)
Register-TarefaCitizenTech -Nome 'CitizenTech_Monitor_Alertas' -Acao $acao -Gatilho $gatilho `
    -Descricao "AlertaEncosta: verifica CPU, memória e disco a cada $($Config.IntervaloMonitorMin) min (Monitor-Recursos.ps1)"

# Os conjuntos do perfmon não iniciam sozinhos após reiniciar: esta tarefa liga os dois no boot.
$acaoBoot    = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c logman start CitizenTech_Monitor & logman start CitizenTech_Alertas'
$gatilhoBoot = New-ScheduledTaskTrigger -AtStartup
Register-TarefaCitizenTech -Nome 'CitizenTech_Iniciar_Coletores' -Acao $acaoBoot -Gatilho $gatilhoBoot `
    -Descricao 'AlertaEncosta: inicia os coletores do Monitor de Desempenho no boot'

Start-ScheduledTask -TaskName 'CitizenTech_Monitor_Alertas'
Start-Sleep -Seconds 8

Invoke-Evidencia -Titulo 'Tarefas agendadas do monitoramento' -Arquivo '05-monitoramento\tarefas-agendadas.txt' -Comando {
    Get-ScheduledTask -TaskName 'CitizenTech_*' | Format-Table TaskName, State -AutoSize
    Get-ScheduledTask -TaskName 'CitizenTech_*' | Get-ScheduledTaskInfo |
        Format-Table TaskName, LastRunTime, LastTaskResult, NextRunTime -AutoSize
}

Write-Host ''
Write-Host 'Prints desta etapa (05-monitoramento):' -ForegroundColor DarkGray
Write-Host '  perfmon-conjunto-ativo.png  perfmon > Conjuntos de Coletores de Dados > Definido pelo Usuário' -ForegroundColor DarkGray
Write-Host '  perfmon-grafico.png         perfmon > Monitor de Desempenho, com os 3 contadores adicionados' -ForegroundColor DarkGray
Write-Host '  monitor-recursos.png        execução do C:\Scripts\Monitor-Recursos.ps1 no terminal' -ForegroundColor DarkGray
Write-Host '  evento-alerta.png           Visualizador de Eventos: Application (9001) ou Diagnosis-PLA (2031)' -ForegroundColor DarkGray
Write-Host '  agendador-tarefas.png       taskschd.msc com a tarefa e a aba Histórico' -ForegroundColor DarkGray
Write-Host 'Dica para o vídeo: C:\Scripts\Gerar-Carga.ps1 gera carga real de CPU e dispara os alertas.' -ForegroundColor Green
Write-Host 'Próximo passo: .\08-Tolerancia-Falhas.ps1' -ForegroundColor Green
