#Requires -RunAsAdministrator
<#
.SYNOPSIS
    ETAPA 6 (item 8.1 do roteiro) - Ficha da infraestrutura: bloco de validação final.

.DESCRIPTION
    Roda o bloco de validação do roteiro (com algumas linhas de apoio)
    e grava tudo em evidencias\08-validacao-final\ficha-infraestrutura.txt.

    Para o print (08-validacao-final\ficha-infraestrutura.png): maximize a janela do
    PowerShell antes de rodar. Se não couber em uma tela, tire dois prints em sequência.

    Esperado: TcpTestSucceeded True, todos os recursos Installed, site e pool Started,
    serviços Running.
#>
. "$PSScriptRoot\00-Config.ps1"
. "$PSScriptRoot\lib\Comum.ps1"

Import-Module WebAdministration, ActiveDirectory, GroupPolicy

Invoke-Evidencia -Titulo '=== FICHA DA INFRAESTRUTURA ===' -Arquivo '08-validacao-final\ficha-infraestrutura.txt' -Comando {
    hostname
    ipconfig /all
    nslookup $FQDNServidor
    Test-NetConnection -ComputerName $FQDNServidor -Port 80 |
        Format-List ComputerName, RemoteAddress, RemotePort, TcpTestSucceeded
    Get-ADDomain | Format-Table Name, DNSRoot, NetBIOSName -AutoSize
    Get-WindowsFeature -Name Web-Server, AD-Domain-Services, DNS, FS-FileServer, FS-DFS-Namespace |
        Format-Table Name, InstallState -AutoSize
    Get-Website | Format-Table Name, State, PhysicalPath -AutoSize
    "Pool $($Config.Pool): $((Get-WebAppPoolState -Name $Config.Pool).Value)"
    Get-Service W3SVC, WAS, DNS, NTDS, Dfs | Format-Table Name, Status -AutoSize
    Get-SmbShare | Format-Table Name, Path -AutoSize
    Get-GPO -All | Format-Table DisplayName, GpoStatus -AutoSize
}

Invoke-Evidencia -Titulo 'Validação complementar (monitoramento, recuperação e auditoria)' -Arquivo '08-validacao-final\validacao-extra.txt' -Comando {
    'Aplicação pelo nome DNS:'
    Invoke-WebRequest -Uri "http://$($Config.NomeDnsApp).$($Config.Dominio)" -UseBasicParsing |
        Format-Table StatusCode, StatusDescription -AutoSize
    'Coletores do Monitor de Desempenho:'
    logman query | Select-String 'CitizenTech'
    'Tarefas agendadas:'
    Get-ScheduledTask -TaskName 'CitizenTech_*' | Get-ScheduledTaskInfo |
        Format-Table TaskName, LastRunTime, LastTaskResult, NextRunTime -AutoSize
    'Recuperação do W3SVC:'
    sc.exe qfailure W3SVC
    'Auditoria (Logon e Sistema de Arquivos):'
    auditpol /get '/subcategory:{0CCE9215-69AE-11D9-BED3-505054503030},{0CCE921D-69AE-11D9-BED3-505054503030}'
    'DFS:'
    Get-DfsnRoot | Format-Table Path, State -AutoSize
    'Usuários e grupos da OU CitizenTech:'
    Get-ADUser -Filter * -SearchBase $CaminhoOU | Format-Table SamAccountName, Enabled -AutoSize
    Get-ADGroup -Filter * -SearchBase $CaminhoOU | Format-Table Name, GroupScope -AutoSize
}

Write-Host ''
Write-Host 'Próximo passo: .\10-Coletar-Evidencias.ps1 (junta os logs e gera o .zip das evidências)' -ForegroundColor Green
