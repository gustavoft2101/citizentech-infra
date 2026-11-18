<#
.SYNOPSIS
    Tirar-Print.ps1 - Salva um print da tela do servidor (PNG) na pasta evidencias do repositório.

.DESCRIPTION
    Usado para gerar os prints da entrega direto de dentro da VM, na resolução real da tela.
    Com -Comando, limpa a tela, mostra o comando, executa e tira o print da saída.
    Com -Atraso, o print é tirado em segundo plano depois de N segundos: dá tempo de deixar
    na frente a janela que deve aparecer no print (o console volta na hora).
    Com -Minimizar, o próprio console é minimizado para mostrar a janela que está atrás dele
    (perfmon, Visualizador de Eventos, Agendador de Tarefas, propriedades de pasta...).

.EXAMPLE
    Z:\scripts\Tirar-Print.ps1 02-ad-dns\get-addomain.png -Comando { Get-ADDomain | Format-List Name, DNSRoot }
    Z:\scripts\Tirar-Print.ps1 01-rede\winver.png -Atraso 5 ; winver
    Z:\scripts\Tirar-Print.ps1 03-iis\aba-seguranca.png -Minimizar
#>
param(
    [Parameter(Mandatory)][string]$Arquivo,
    [scriptblock]$Comando,
    [int]$Atraso = 0,
    [switch]$Minimizar,
    [switch]$Filho
)

if ([System.IO.Path]::IsPathRooted($Arquivo)) {
    $destino = $Arquivo
} else {
    $destino = Join-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'evidencias') $Arquivo
}

# Com -Comando: a tela fica só com o comando e a saída dele, como no terminal.
if ($Comando) {
    Clear-Host
    Write-Host "PS $((Get-Location).Path)> " -NoNewline
    $textoComando = $Comando.ToString().Trim()
    Write-Host $textoComando -ForegroundColor Yellow
    & $Comando | Out-Host
    Start-Sleep -Milliseconds 700
}

# Com -Minimizar: esconde este console para a janela de trás aparecer no print.
if ($Minimizar -and -not $Filho) {
    if ($Atraso -lt 3) { $Atraso = 3 }
    if (-not ('CitizenTech.Janela' -as [type])) {
        Add-Type -Namespace CitizenTech -Name Janela -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
'@
    }
    $janela = (Get-Process -Id $PID).MainWindowHandle
    if ($janela -ne [System.IntPtr]::Zero) { [CitizenTech.Janela]::ShowWindow($janela, 6) | Out-Null }
}

# Com atraso: abre um PowerShell oculto que espera e tira o print, e devolve o console na hora.
if ($Atraso -gt 0 -and -not $Filho) {
    $argumentos = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Arquivo `"$destino`" -Atraso $Atraso -Filho"
    Start-Process -FilePath powershell.exe -ArgumentList $argumentos -WindowStyle Hidden
    return
}

if ($Atraso -gt 0) { Start-Sleep -Seconds $Atraso }

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$tela   = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$imagem = New-Object System.Drawing.Bitmap $tela.Width, $tela.Height
$grafico = [System.Drawing.Graphics]::FromImage($imagem)
$grafico.CopyFromScreen($tela.Location, [System.Drawing.Point]::Empty, $tela.Size)

New-Item -ItemType Directory -Path (Split-Path $destino) -Force | Out-Null
$imagem.Save($destino, [System.Drawing.Imaging.ImageFormat]::Png)
$grafico.Dispose(); $imagem.Dispose()
if (-not $Filho) { Write-Host "Print salvo em $destino" -ForegroundColor DarkGray }
