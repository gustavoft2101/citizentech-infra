#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ETAPA 5 (itens 7.1 e 7.3 do roteiro) - Recuperação automática do pool, do serviço e do site.

.DESCRIPTION
    São três camadas de proteção, uma para cada tipo de falha:
      1. Pool CitizenTechPool (configuração do IIS)
           rapidFailProtection = False -> o pool não é desativado depois de várias quedas
           autoStart = True e startMode = AlwaysRunning -> o pool sobe junto com o IIS
           Se o processo w3wp.exe cair, o WAS cria outro na próxima requisição.
      2. Serviços W3SVC e WAS (aba Recuperação do services.msc, via sc.exe failure)
           Se o serviço cair sozinho (travamento), o Windows reinicia em 5 s, 10 s e 30 s.
      3. Tarefa agendada CitizenTech_Recuperacao -> C:\Scripts\Recupera-Site.ps1 a cada 1 min
           Cobre o que o Windows não cobre: serviço parado com Stop-Service, pool ou site
           parados no Gerenciador do IIS, ou site sem responder (iisreset).
#>
. "$PSScriptRoot\00-Config.ps1"
. "$PSScriptRoot\lib\Comum.ps1"

Write-Etapa 'ETAPA 5 - Tolerância a falhas e recuperação automática'

Import-Module WebAdministration
$caminhoPool = "IIS:\AppPools\$($Config.Pool)"

# ---------------------------------------------------------------- 7.1 Pool
Write-Passo '7.1 Recuperação automática do pool do IIS'
Set-ItemProperty $caminhoPool -Name failure.rapidFailProtection -Value $false
Set-ItemProperty $caminhoPool -Name autoStart                   -Value $true
Set-ItemProperty $caminhoPool -Name startMode                   -Value 'AlwaysRunning'
Set-ItemProperty $caminhoPool -Name processModel.pingingEnabled -Value $true    # o WAS testa se o w3wp responde
Set-ItemProperty "IIS:\Sites\$($Config.Site)" -Name serverAutoStart -Value $true
Write-Ok 'Pool: rapidFailProtection desligado, autoStart ligado, AlwaysRunning, ping de saúde ligado.'

Invoke-Evidencia -Titulo 'Configuração de recuperação do pool' -Arquivo '06-teste-falha\pool-configuracao.txt' -Comando {
    $p = Get-Item $caminhoPool
    [pscustomobject]@{
        Pool                = $p.name
        Estado              = $p.state
        Runtime             = "'$($p.managedRuntimeVersion)' (vazio = sem código gerenciado)"
        AutoStart           = $p.autoStart
        StartMode           = $p.startMode
        RapidFailProtection = $p.failure.rapidFailProtection
        PingHabilitado      = $p.processModel.pingingEnabled
    } | Format-List
}

# ---------------------------------------------------------------- 7.1 Serviços
Write-Passo '7.1 Recuperação dos serviços W3SVC e WAS (aba Recuperação)'
foreach ($servico in @('W3SVC', 'WAS')) {
    # reset= 86400 -> o contador de falhas zera depois de 1 dia sem falhas
    # actions= reiniciar após 5 s (1ª falha), 10 s (2ª) e 30 s (3ª e seguintes)
    sc.exe failure $servico reset= 86400 actions= restart/5000/restart/10000/restart/30000 | Out-Null
    # failureflag 1 -> também aplica as ações quando o serviço para com código de erro
    sc.exe failureflag $servico 1 | Out-Null
    Write-Ok "$servico com reinício automático configurado."
}
Set-Service -Name W3SVC -StartupType Automatic

Invoke-Evidencia -Titulo 'sc.exe qfailure W3SVC e WAS' -Arquivo '06-teste-falha\sc-qfailure.txt' -Comando {
    sc.exe qfailure W3SVC
    sc.exe qfailure WAS
}

# ---------------------------------------------------------------- 7.3 Script e tarefa de recuperação
Write-Passo '7.3 Script e tarefa de recuperação do site e do pool'
New-Item -Path $Config.PastaScripts, $Config.PastaLogs -ItemType Directory -Force | Out-Null
if (-not [System.Diagnostics.EventLog]::SourceExists('CitizenTechRecuperacao')) {
    New-EventLog -LogName Application -Source 'CitizenTechRecuperacao'
}
Copy-Item "$PSScriptRoot\Recupera-Site.ps1", "$PSScriptRoot\Teste-Falha.ps1" -Destination $Config.PastaScripts -Force
Get-ChildItem $Config.PastaScripts -Filter *.ps1 | Unblock-File
$recupera = Join-Path $Config.PastaScripts 'Recupera-Site.ps1'

$argumentos = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$recupera`" " +
              "-Site `"$($Config.Site)`" -Pool `"$($Config.Pool)`""
$acao    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argumentos
$gatilho = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
               -RepetitionInterval (New-TimeSpan -Minutes $Config.IntervaloRecuperacaoMin) `
               -RepetitionDuration (New-TimeSpan -Days 3650)
Register-TarefaCitizenTech -Nome 'CitizenTech_Recuperacao' -Acao $acao -Gatilho $gatilho `
    -Descricao "AlertaEncosta: verifica e religa W3SVC, WAS, pool e site a cada $($Config.IntervaloRecuperacaoMin) min (Recupera-Site.ps1)"

Invoke-Evidencia -Titulo 'Execução manual do Recupera-Site.ps1 (com tudo no ar)' -Arquivo '06-teste-falha\recupera-site-execucao.txt' -Comando {
    & $recupera -Site $Config.Site -Pool $Config.Pool
    Get-ScheduledTask -TaskName 'CitizenTech_Recuperacao' | Format-Table TaskName, State -AutoSize
    Get-ScheduledTask -TaskName 'CitizenTech_Recuperacao' | Get-ScheduledTaskInfo |
        Format-Table TaskName, LastRunTime, NextRunTime -AutoSize
}

Write-Host ''
Write-Host 'Agora faça o teste de falha (prints em 06-teste-falha):' -ForegroundColor Green
Write-Host '  powershell -ExecutionPolicy Bypass -File C:\Scripts\Teste-Falha.ps1                 (roteiro: Stop-Service)'
Write-Host '  powershell -ExecutionPolicy Bypass -File C:\Scripts\Teste-Falha.ps1 -Cenario Crash  (travamento: volta em segundos)'
Write-Host '  powershell -ExecutionPolicy Bypass -File C:\Scripts\Teste-Falha.ps1 -Cenario Pool   (pool parado)'
Write-Host '  Get-Content C:\Scripts\logs\recuperacao.log'
Write-Host 'Prints: sc-qfailure.png, services-recuperacao.png (services.msc > W3SVC > aba Recuperação),' -ForegroundColor DarkGray
Write-Host '        teste-falha-etapas.png, navegador-voltou.png e recuperacao-log.png' -ForegroundColor DarkGray
Write-Host 'Depois: .\09-Validacao-Final.ps1' -ForegroundColor Green
