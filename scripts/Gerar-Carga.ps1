<#
.SYNOPSIS
    Gerar-Carga.ps1 - Gera carga REAL de CPU para demonstrar os alertas no vídeo.

.DESCRIPTION
    Abre um processo de cálculo por núcleo durante alguns segundos (padrão: 90 s).
    Durante a carga:
      - o alerta nativo do Monitor de Desempenho (CitizenTech_Alertas) dispara e grava
        o evento 2031 em Logs de Aplicativos e Serviços > Microsoft > Windows > Diagnosis-PLA > Operacional
      - o Monitor-Recursos.ps1 é executado e mostra a linha amarela "CPU alta"
    Ao final todos os processos de carga são encerrados.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Scripts\Gerar-Carga.ps1
    powershell -ExecutionPolicy Bypass -File C:\Scripts\Gerar-Carga.ps1 -Segundos 60
#>
param(
    [int]$Segundos = 90,
    [int]$Nucleos  = [Environment]::ProcessorCount
)

Write-Host "Gerando carga de CPU em $Nucleos núcleo(s) por $Segundos segundos..." -ForegroundColor Yellow
$trabalhos = 1..$Nucleos | ForEach-Object {
    Start-Job -ScriptBlock {
        param($duracao)
        $fim = (Get-Date).AddSeconds($duracao)
        while ((Get-Date) -lt $fim) { [math]::Sqrt((Get-Random)) | Out-Null }
    } -ArgumentList $Segundos
}

Start-Sleep -Seconds 20
Write-Host "`nCPU agora: $((Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average)%" -ForegroundColor Yellow
$monitor = Join-Path $PSScriptRoot 'Monitor-Recursos.ps1'
if (Test-Path $monitor) {
    Write-Host "Executando o Monitor-Recursos.ps1 durante a carga:" -ForegroundColor Yellow
    & $monitor
}

Write-Host "`nAguardando o fim da carga..." -ForegroundColor Yellow
$trabalhos | Wait-Job | Out-Null
$trabalhos | Remove-Job -Force
Write-Host 'Carga encerrada.' -ForegroundColor Green

Write-Host "`nAlertas do Monitor de Desempenho (evento 2031) nos últimos 5 minutos:" -ForegroundColor Cyan
Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnosis-PLA/Operational'; Id = 2031; StartTime = (Get-Date).AddMinutes(-5) } -ErrorAction SilentlyContinue |
    Select-Object -First 10 TimeCreated, Id, @{ n = 'Mensagem'; e = { ($_.Message -split "`r?`n")[0] } } |
    Format-Table -AutoSize -Wrap
