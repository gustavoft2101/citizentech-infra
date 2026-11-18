<#
.SYNOPSIS
    Funções de apoio usadas pelos scripts de etapa (01 a 10).

.DESCRIPTION
    Carregado com:  . "$PSScriptRoot\lib\Comum.ps1"

    Por que existem estas funções:
      - Invoke-Evidencia: roda um comando, mostra a saída na tela (para o print)
        e salva a mesma saída em evidencias\<pasta>\<arquivo>.txt (para o GitHub).
      - Get-NomeConta: o Windows em português chama "Everyone" de "Todos",
        "Domain Users" de "Usuários do domínio" etc. Usando o SID (identificador
        fixo) o script funciona em qualquer idioma.
      - Get-ContadorLocal: o mesmo problema acontece com os contadores do
        Monitor de Desempenho ("% Processor Time" vira "% Tempo de Processador").
#>

function Write-Etapa {
    param([Parameter(Mandatory)][string]$Texto)
    Write-Host ''
    Write-Host ('=' * 70) -ForegroundColor Cyan
    Write-Host "  $Texto" -ForegroundColor Cyan
    Write-Host ('=' * 70) -ForegroundColor Cyan
}

function Write-Passo {
    param([Parameter(Mandatory)][string]$Texto)
    Write-Host ''
    Write-Host ">> $Texto" -ForegroundColor Yellow
}

function Write-Ok {
    param([Parameter(Mandatory)][string]$Texto)
    Write-Host "   [OK] $Texto" -ForegroundColor Green
}

function Write-Aviso {
    param([Parameter(Mandatory)][string]$Texto)
    Write-Host "   [AVISO] $Texto" -ForegroundColor Magenta
}

function Invoke-Evidencia {
    <#
      Executa um comando, mostra a saída e grava em evidencias\<Arquivo>.
      Exemplo:
        Invoke-Evidencia -Titulo 'ipconfig /all' -Arquivo '01-rede\ipconfig-all.txt' -Comando { ipconfig /all }
    #>
    param(
        [Parameter(Mandatory)][string]$Titulo,
        [Parameter(Mandatory)][string]$Arquivo,
        [Parameter(Mandatory)][scriptblock]$Comando
    )
    # Dentro desta função os erros não interrompem: queremos registrar o erro na evidência.
    $ErrorActionPreference = 'Continue'

    $destino = Join-Path $PastaEvidencias $Arquivo
    New-Item -ItemType Directory -Path (Split-Path $destino) -Force | Out-Null

    $textoComando = $Comando.ToString().Trim()
    Write-Host ''
    Write-Host "==== $Titulo ====" -ForegroundColor Cyan
    Write-Host "PS C:\> $textoComando" -ForegroundColor DarkGray

    try {
        # *>&1 junta todas as saídas (normal, erro, Write-Host); erros viram texto simples.
        $saida = & $Comando *>&1 | ForEach-Object {
            if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { $_ }
        } | Out-String -Width 220
    }
    catch {
        $saida = "ERRO: $($_.Exception.Message)"
    }

    Write-Host $saida.TrimEnd()

    $cabecalho = @(
        "==== $Titulo ===="
        "Servidor : $env:COMPUTERNAME"
        "Data/hora: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        "Comando  : $textoComando"
        ('-' * 70)
    ) -join "`r`n"
    Set-Content -Path $destino -Value ($cabecalho + "`r`n" + $saida) -Encoding UTF8
    Write-Host "   (saída salva em evidencias\$Arquivo)" -ForegroundColor DarkGray
}

function Get-NomeConta {
    <#
      Converte um SID conhecido no nome da conta no idioma do Windows instalado.
        S-1-1-0       Everyone / Todos
        S-1-5-11      Authenticated Users / Usuários autenticados
        S-1-5-17      IUSR (usuário anônimo do IIS)
        S-1-5-18      SYSTEM / SISTEMA
        S-1-5-32-544  Administrators / Administradores
        S-1-5-32-568  IIS_IUSRS
        <SID-do-domínio>-513  Domain Users / Usuários do domínio
    #>
    param([Parameter(Mandatory)][string]$Sid)
    $objetoSid = New-Object System.Security.Principal.SecurityIdentifier($Sid)
    return $objetoSid.Translate([System.Security.Principal.NTAccount]).Value
}

function New-RegraNtfs {
    <# Cria uma regra de permissão NTFS herdada por subpastas e arquivos. #>
    param(
        [Parameter(Mandatory)][string]$Conta,          # nome (DOMINIO\grupo) ou SID (S-1-...)
        [Parameter(Mandatory)][string]$Direitos,       # ex.: ReadAndExecute, Modify, FullControl
        [string]$Tipo = 'Allow'
    )
    if ($Conta -match '^S-1-') {
        $identidade = New-Object System.Security.Principal.SecurityIdentifier($Conta)
    } else {
        $identidade = New-Object System.Security.Principal.NTAccount($Conta)
    }
    return New-Object System.Security.AccessControl.FileSystemAccessRule(
        $identidade, $Direitos, 'ContainerInherit,ObjectInherit', 'None', $Tipo)
}

function Get-ContadorLocal {
    <#
      Recebe o caminho de um contador em inglês e devolve o nome no idioma do Windows.
        Get-ContadorLocal '\Processor(_Total)\% Processor Time'
        -> em inglês   : \Processor(_Total)\% Processor Time
        -> em português: \Processador(_Total)\% Tempo de Processador
      Como funciona: o Windows guarda cada contador com um número fixo (índice).
      Procuramos o índice do nome em inglês (registro Perflib\009) e pedimos ao
      Windows (pdh.dll) o nome desse índice no idioma atual.
    #>
    param([Parameter(Mandatory)][string]$CaminhoIngles)

    if ($CaminhoIngles -notmatch '^\\(?<objeto>[^\\(]+)(?<instancia>\([^)]*\))?\\(?<contador>.+)$') {
        return $CaminhoIngles
    }
    $objeto    = $Matches['objeto']
    $instancia = $Matches['instancia']
    $contador  = $Matches['contador']

    try {
        if (-not ('PdhNomes' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class PdhNomes {
    [DllImport("pdh.dll", CharSet = CharSet.Unicode)]
    private static extern uint PdhLookupPerfNameByIndex(string maquina, uint indice, StringBuilder nome, ref uint tamanho);
    public static string Nome(uint indice) {
        uint tamanho = 1024;
        StringBuilder sb = new StringBuilder((int)tamanho);
        return PdhLookupPerfNameByIndex(null, indice, sb, ref tamanho) == 0 ? sb.ToString() : null;
    }
}
'@
        }
        if (-not $script:IndicesContadores) {
            $lista = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Perflib\009' -Name Counter).Counter
            $script:IndicesContadores = @{}
            for ($i = 0; $i -lt ($lista.Count - 1); $i += 2) {
                $nome = $lista[$i + 1]
                if ($nome -and -not $script:IndicesContadores.ContainsKey($nome)) {
                    $script:IndicesContadores[$nome] = [uint32]$lista[$i]
                }
            }
        }
        $objetoLocal   = [PdhNomes]::Nome($script:IndicesContadores[$objeto])
        $contadorLocal = [PdhNomes]::Nome($script:IndicesContadores[$contador])
        if ($objetoLocal -and $contadorLocal) {
            return "\$objetoLocal$instancia\$contadorLocal"
        }
    }
    catch {
        Write-Aviso "Não foi possível traduzir '$CaminhoIngles' ($($_.Exception.Message)). Usando o nome em inglês."
    }
    return $CaminhoIngles
}

function Register-TarefaCitizenTech {
    <#
      Registra (ou atualiza) uma tarefa agendada que roda como SYSTEM com privilégio máximo.
      O nome da conta SYSTEM é obtido pelo SID S-1-5-18, então funciona em qualquer idioma.
    #>
    param(
        [Parameter(Mandatory)][string]$Nome,
        [Parameter(Mandatory)][string]$Descricao,
        [Parameter(Mandatory)]$Acao,
        [Parameter(Mandatory)]$Gatilho
    )
    $contaSistema = Get-NomeConta 'S-1-5-18'
    $principal    = New-ScheduledTaskPrincipal -UserId $contaSistema -LogonType ServiceAccount -RunLevel Highest
    $opcoes       = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew `
                        -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName $Nome -Description $Descricao -Action $Acao -Trigger $Gatilho `
        -Principal $principal -Settings $opcoes -Force | Out-Null
    Write-Ok "Tarefa agendada '$Nome' registrada (executa como $contaSistema)."
}
