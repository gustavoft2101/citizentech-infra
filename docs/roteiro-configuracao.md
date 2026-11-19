# Roteiro de configuração – SRV-CITIZENTECH (AlertaEncosta)

Este documento é o passo a passo usado para montar a infraestrutura. Ele segue a numeração do roteiro da atividade (itens 3.1 a 8.3). Em cada item há:

- **Script**: o que rodar (faz tudo do item e salva a saída em `evidencias/`);
- **Comandos principais**: o que o script executa, para entender e explicar;
- **Saída esperada** e **print** (nome do arquivo `.png` a salvar em `evidencias/`).

> Todos os comandos rodam em **PowerShell como Administrador** (botão direito > *Executar como administrador*).

## Sumário

0. [Preparar a VM e copiar o repositório](#0-preparar-a-vm-e-copiar-o-repositório)
1. [Etapa 1 – Rede, AD e DNS (itens 3.1 a 3.5)](#1-etapa-1--rede-ad-e-dns-itens-31-a-35)
2. [Etapa 2 – Aplicação no IIS (itens 4.1 a 4.5)](#2-etapa-2--aplicação-no-iis-itens-41-a-45)
3. [Etapa 3 – GPO, RDP, DFS, auditoria (itens 5.1 a 5.4)](#3-etapa-3--gpo-rdp-dfs-e-auditoria-itens-51-a-54)
4. [Etapa 4 – Monitoramento com alertas (itens 6.1 a 6.3)](#4-etapa-4--monitoramento-com-alertas-itens-61-a-63)
5. [Etapa 5 – Teste de falha e recuperação (itens 7.1 a 7.3)](#5-etapa-5--teste-de-falha-e-recuperação-automática-itens-71-a-73)
6. [Etapa 6 – Validação final e evidências (itens 8.1 a 8.3)](#6-etapa-6--validação-final-e-evidências-itens-81-a-83)
7. [Caminho B – API AlertaEncosta (Java) no IIS](#7-caminho-b--api-alertaencosta-java-21--spring-boot-no-iis--item-43)
8. [Erros comuns e como resolver](#8-erros-comuns-e-como-resolver)

---

## 0. Preparar a VM e copiar o repositório

### 0.1 Valores do ambiente

| Item | Valor usado |
|---|---|
| Hipervisor | VirtualBox, VMware Workstation, Hyper-V ou Azure |
| VM | Windows Server 2022 (ou 2019) **Desktop Experience**, 1 ou 2 vCPU, 4 GB RAM, disco de 60 GB (veja o aviso sobre Hyper-V no item 8) |
| Rede | Adaptador em modo **Bridge** |
| Hostname | `SRV-CITIZENTECH` |
| Domínio | `citizentech.local` |
| IP | `192.168.200.230/24`, gateway `192.168.200.1` (os da nossa rede; ajuste para a sua no `00-Config.ps1`) |

Anote em um bloco de notas **fora do repositório**: senha do Administrador, senha DSRM e senha dos usuários de teste.

### 0.2 Criar a VM

1. Baixe a ISO de avaliação do Windows Server 2022 no Microsoft Evaluation Center (180 dias grátis).
2. Crie a VM com os recursos acima e a placa de rede em **Bridge** (no VirtualBox: *Configurações > Rede > Conectado a: Placa em modo Bridge*).
3. Na instalação escolha a edição **"Standard Evaluation (Desktop Experience)"** (a que tem interface gráfica). No VirtualBox, se usar a instalação desassistida, confira a edição escolhida.
4. Defina a senha do Administrador local.

> Se a sua rede Wi-Fi não aceitar o modo Bridge (a VM fica sem IP), use uma rede *Host-only* para o laboratório (no VirtualBox o padrão é `192.168.56.0/24`): no `00-Config.ps1` coloque `IP = '192.168.56.10'` e `Gateway = '192.168.56.1'`.

### 0.3 Copiar o repositório para a VM (faça ANTES do script 01)

O script 01 aponta o DNS da VM para ela mesma; até o script 03 configurar os encaminhadores, a VM fica sem resolver nomes da internet. Por isso copie o repositório antes.

Opção A – navegador da VM: no GitHub, *Code > Download ZIP*, extraia em `C:\` e renomeie a pasta para `C:\citizentech-infra`.

Opção B – PowerShell (repositório público):

```powershell
New-Item C:\Temp -ItemType Directory -Force | Out-Null
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri 'https://github.com/gustavoft2101/citizentech-infra/archive/refs/heads/main.zip' -OutFile C:\Temp\repo.zip -UseBasicParsing
Expand-Archive C:\Temp\repo.zip -DestinationPath C:\ -Force
Rename-Item C:\citizentech-infra-main citizentech-infra
```

Opção C – pasta compartilhada do hipervisor (VirtualBox: *Dispositivos > Pastas Compartilhadas*) ou arrastar e soltar.

### 0.4 Liberar a execução dos scripts

```powershell
cd C:\citizentech-infra\scripts
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force   # vale só para esta janela
Get-ChildItem C:\citizentech-infra -Recurse | Unblock-File          # tira a marca de "baixado da internet"
```

### 0.5 Ajustar o `00-Config.ps1`

Abra `scripts\00-Config.ps1` no Bloco de Notas (ou PowerShell ISE) e confira `IP`, `Prefixo` e `Gateway`. Para descobrir a sua rede: `ipconfig` na VM antes do script 01 (o próprio script 01 também mostra a configuração atual e pede confirmação).

---

## 1. Etapa 1 – Rede, AD e DNS (itens 3.1 a 3.5)

### 3.1 Criar a VM e instalar o Windows Server

Feito no item 0.2.

- **Print** `01-rede/winver.png`: tela inicial do Windows Server com a janela do `winver` aberta (Win+R > `winver`).
- O script 01 também salva `01-rede/versao-windows.txt`.

### 3.2 Renomear o servidor e definir IP fixo

**Script** (rode no console da VM, não por RDP):

```powershell
.\01-Rede-Hostname.ps1
```

**Comandos principais**

```powershell
Get-NetAdapter                                                     # descobre o ifIndex da placa conectada
Set-NetIPInterface -InterfaceIndex 12 -AddressFamily IPv4 -Dhcp Disabled
New-NetIPAddress -InterfaceIndex 6 -IPAddress 192.168.200.230 -PrefixLength 24 -DefaultGateway 192.168.200.1
Set-DnsClientServerAddress -InterfaceIndex 6 -ServerAddresses 192.168.200.230
Set-TimeZone -Id 'E. South America Standard Time'                  # logs com horário de Brasília
Rename-Computer -NewName 'SRV-CITIZENTECH' -Restart
```

O script escolhe sozinho o `ifIndex`, mostra a configuração atual, pede confirmação e reinicia.

**Saída esperada**: tabela com `IPAddress 192.168.200.230`, `PrefixLength 24`, `InterfaceIndex` e `AddressFamily IPv4`; depois o reinício.

O print do `ipconfig /all` (`01-rede/ipconfig-all.png`) fica melhor **depois** do script 03, quando aparecem o hostname novo e o sufixo `citizentech.local`. O script 03 salva `01-rede/ipconfig-all.txt`.

### 3.3 Instalar o Active Directory e promover o domínio

**Script**

```powershell
.\02-AD-DNS.ps1
```

**Comandos principais**

```powershell
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools
Install-ADDSForest -DomainName 'citizentech.local' -DomainNetbiosName 'CITIZENTECH' -InstallDns `
    -SafeModeAdministratorPassword (Read-Host -AsSecureString 'Senha DSRM') -NoRebootOnCompletion -Force
Restart-Computer
```

**Saída esperada**: `Success True` para AD-Domain-Services; `Status Success` e a mensagem de operação concluída no `Install-ADDSForest`. Avisos amarelos sobre delegação de DNS e criptografia são normais em laboratório.

Depois do reinício faça logon como **`CITIZENTECH\Administrator`** (mesma senha do Administrador local).

### 3.4 Validar DNS e domínio  ·  3.5 Usuários e grupos

**Script**

```powershell
.\03-AD-Usuarios.ps1
```

**Comandos principais**

```powershell
# DNS: internet, zona reversa e nome da aplicação
Set-DnsServerForwarder -IPAddress 8.8.8.8, 1.1.1.1
Add-DnsServerPrimaryZone -NetworkId '192.168.200.0/24' -ReplicationScope Forest
Add-DnsServerResourceRecordPtr -ZoneName '200.168.192.in-addr.arpa' -Name '230' -PtrDomainName 'srv-citizentech.citizentech.local.'
Add-DnsServerResourceRecordA -ZoneName 'citizentech.local' -Name 'alertaencosta' -IPv4Address 192.168.200.230

# 3.4 validação
ipconfig /all
Get-ADDomain | Select-Object Name, DNSRoot, NetBIOSName, DomainMode
# depois da promoção o Windows aponta o DNS para 127.0.0.1/::1; voltamos para o IP do servidor
Set-DnsClientServerAddress -InterfaceIndex 6 -ServerAddresses 192.168.200.230
nslookup srv-citizentech.citizentech.local 192.168.200.230
Get-DnsServerZone

# 3.5 OU, grupos e usuários
New-ADOrganizationalUnit -Name 'CitizenTech' -Path 'DC=citizentech,DC=local'
New-ADGroup -Name 'GG_CitizenTech_Admins'     -GroupScope Global -GroupCategory Security -Path 'OU=CitizenTech,DC=citizentech,DC=local'
New-ADGroup -Name 'GG_CitizenTech_Operadores' -GroupScope Global -GroupCategory Security -Path 'OU=CitizenTech,DC=citizentech,DC=local'
New-ADUser -Name 'Ana Souza' -SamAccountName 'ana.souza' -UserPrincipalName 'ana.souza@citizentech.local' `
    -Path 'OU=CitizenTech,DC=citizentech,DC=local' -AccountPassword (Read-Host -AsSecureString 'Senha') -Enabled $true
Add-ADGroupMember -Identity 'GG_CitizenTech_Admins' -Members 'ana.souza'
# (o script cria também carlos.lima e beatriz.alves no grupo de operadores)

Get-ADUser -Filter * -SearchBase 'OU=CitizenTech,DC=citizentech,DC=local' | Select-Object Name, SamAccountName, Enabled
Get-ADGroupMember -Identity 'GG_CitizenTech_Admins'
```

A zona reversa é um extra: sem ela o `nslookup` mostra `Servidor: UnKnown`.

**Saída esperada**

- `ipconfig /all`: *Nome do host* `SRV-CITIZENTECH`, *Sufixo DNS primário* `citizentech.local`, DHCP desabilitado, IP, máscara, gateway e DNS `192.168.200.230`.
- `Get-ADDomain`: `Name citizentech`, `DNSRoot citizentech.local`.
- `nslookup`: servidor `srv-citizentech.citizentech.local`, endereço `192.168.200.230`.
- `Get-DnsServerZone`: `citizentech.local` como **Primary**, integrada ao AD, e a zona reversa.
- Usuários `ana.souza`, `carlos.lima` e `beatriz.alves` com `Enabled True`; membros corretos nos dois grupos.

**Prints**: `01-rede/ipconfig-all.png`, `02-ad-dns/get-addomain.png`, `02-ad-dns/nslookup.png`, `02-ad-dns/get-dnsserverzone.png`, `02-ad-dns/usuarios-grupos.png` (os dois comandos de validação do 3.5).

---

## 2. Etapa 2 – Aplicação no IIS (itens 4.1 a 4.5)

**Caminhos usados: A e B.** A pasta [`app/alertaencosta-web`](../app/alertaencosta-web) é o portal público do AlertaEncosta: situação de risco por setor, rotas seguras, pontos de apoio e orientações, com dados simulados e recursos de acessibilidade (alto contraste e letra maior). A API REST do AlertaEncosta (Java/Spring Boot) é publicada no mesmo IIS pelo [Caminho B](#7-caminho-b--api-alertaencosta-java-21--spring-boot-no-iis--item-43).

**Script** (itens 4.1, 4.2 e 4.4)

```powershell
.\04-IIS-Aplicacao.ps1
```

### 4.1 Instalar o IIS

```powershell
Install-WindowsFeature -Name Web-Server, Web-Mgmt-Console, Web-Scripting-Tools, Web-Http-Logging, `
    Web-Request-Monitor, Web-Http-Tracing -IncludeManagementTools
Get-WindowsFeature -Name Web-* | Where-Object Installed
```

**Saída esperada**: `Success True` e a lista de recursos `Web-*` com `Installed`. **Print** `03-iis/get-windowsfeature-web.png`.

### 4.2 Caminho A – publicar o site

```powershell
New-Item -Path 'C:\inetpub\citizentech' -ItemType Directory -Force
Copy-Item -Path 'C:\citizentech-infra\app\alertaencosta-web\*' -Destination 'C:\inetpub\citizentech' -Recurse -Force
Remove-Website -Name 'Default Web Site'                     # libera a porta 80
New-WebAppPool -Name 'CitizenTechPool'
Set-ItemProperty -Path 'IIS:\AppPools\CitizenTechPool' -Name managedRuntimeVersion -Value ''   # sem código gerenciado
New-Website -Name 'CitizenTech' -Port 80 -PhysicalPath 'C:\inetpub\citizentech' -ApplicationPool 'CitizenTechPool'
New-NetFirewallRule -DisplayName 'CitizenTech - HTTP (80)' -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow

Get-Website -Name 'CitizenTech' | Format-List Name, State, PhysicalPath, ApplicationPool
Get-WebAppPoolState -Name 'CitizenTechPool'
Invoke-WebRequest -Uri 'http://localhost' -UseBasicParsing | Select-Object StatusCode
```

O script também grava `servidor.json` na pasta do site; o rodapé da página mostra *"Servido por SRV-CITIZENTECH (192.168.200.230) · IIS 10.0 · site CitizenTech / pool CitizenTechPool"*, o que prova no print que a página vem do IIS da VM.

O `web.config` do site define `index.html` como documento padrão, os tipos MIME `.json` e `.svg`, desliga a listagem de pastas e adiciona cabeçalhos de segurança.

**Saída esperada**: site `CitizenTech` com `State Started`, `PhysicalPath C:\inetpub\citizentech`, `ApplicationPool CitizenTechPool`; pool `Started`; `StatusCode 200`.

**Prints**: `03-iis/get-website.png`, `03-iis/get-webapppoolstate.png` (com o `Invoke-WebRequest`) e `03-iis/navegador-site.png` – navegador de **outra máquina** (o seu computador) abrindo `http://192.168.200.230` com a página do AlertaEncosta e o rodapé visível.

### 4.4 Permissões NTFS da pasta do site

```powershell
$pasta = Get-Item 'C:\inetpub\citizentech'
$acl = $pasta.GetAccessControl('Access')
$regra = New-Object System.Security.AccessControl.FileSystemAccessRule('IIS_IUSRS','ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')
$acl.SetAccessRule($regra)
# o script adiciona também IUSR (leitura, acesso anônimo) e GG_CitizenTech_Admins (alteração, quem publica)
$pasta.SetAccessControl($acl)     # grava só a DACL (equivale ao Set-Acl do roteiro, sem tocar na auditoria)
Get-Acl 'C:\inetpub\citizentech' | Format-List
```

**Saída esperada**: `IIS_IUSRS Allow ReadAndExecute`, `IUSR Allow ReadAndExecute`, `CITIZENTECH\GG_CitizenTech_Admins Allow Modify`.

**Prints**: `03-iis/get-acl.png` e `03-iis/aba-seguranca.png` (Explorador > `C:\inetpub\citizentech` > Propriedades > Segurança, com `IIS_IUSRS` selecionado).

### 4.5 File Server e compartilhamento

**Script** (itens 4.5, 5.1, 5.2 e 5.3)

```powershell
.\05-FileServer-GPO-RDP-DFS.ps1
```

```powershell
Install-WindowsFeature -Name FS-FileServer -IncludeManagementTools
New-Item -Path 'C:\Shares\CitizenTech' -ItemType Directory -Force
# NTFS: GG_CitizenTech_Admins Modify, Domain Users ReadAndExecute
New-SmbShare -Name 'CitizenTech' -Path 'C:\Shares\CitizenTech' -FullAccess 'CITIZENTECH\GG_CitizenTech_Admins', 'BUILTIN\Administrators'
Grant-SmbShareAccess -Name 'CitizenTech' -AccountName 'CITIZENTECH\Domain Users' -AccessRight Read -Force
Get-SmbShare
```

No Windows em português o grupo se chama *Usuários do domínio*; o script descobre o nome certo pelo SID.

**Saída esperada**: compartilhamento `CitizenTech` com `Path C:\Shares\CitizenTech`; acesso Full para admins e Read para usuários do domínio.

**Prints**: `04-ntfs-gpo/get-smbshare.png` e `04-ntfs-gpo/acesso-share-cliente.png`: no seu computador, Explorador de Arquivos > `\\192.168.200.230\CitizenTech` (ou `\\SRV-CITIZENTECH\CitizenTech`), credencial `CITIZENTECH\ana.souza`, mostrando o arquivo `LEIA-ME-plano-de-contingencia-SIMULADO.txt`.

---

## 3. Etapa 3 – GPO, RDP, DFS e auditoria (itens 5.1 a 5.4)

### 5.1 GPO (política de grupo)

```powershell
New-GPO -Name 'GPO_CitizenTech_Usuarios'
New-GPLink -Name 'GPO_CitizenTech_Usuarios' -Target 'OU=CitizenTech,DC=citizentech,DC=local'
Set-GPRegistryValue -Name 'GPO_CitizenTech_Usuarios' -Key 'HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer' `
    -ValueName 'NoControlPanel' -Type DWord -Value 1
Get-GPOReport -Name 'GPO_CitizenTech_Usuarios' -ReportType Html -Path 'C:\Temp\GPO_Report.html'
Get-GPO -All
```

**Saída esperada**: GPO criada, ligada à OU e relatório HTML (cópia em `evidencias/04-ntfs-gpo/GPO_Report.html`).

**Print** `04-ntfs-gpo/get-gpo-all.png`: saída do `Get-GPO -All`.

**Print** `04-ntfs-gpo/usuario-sem-painel.png`: tela de um usuário comum (`carlos.lima`) tentando abrir o Painel de Controle e recebendo a mensagem de restrição. Em um controlador de domínio, usuários comuns não podem fazer logon por padrão, então escolha uma das opções:

**Opção 1 (recomendada) – VM cliente no domínio** (Windows 10/11 Pro ou outro Windows Server):

```powershell
# no cliente, como administrador local
Set-DnsClientServerAddress -InterfaceIndex <ifIndex> -ServerAddresses 192.168.200.230
Add-Computer -DomainName citizentech.local -Credential CITIZENTECH\Administrator -Restart
```

Depois faça logon como `CITIZENTECH\carlos.lima`, rode `gpresult /r /scope user` (a GPO aparece em *Objetos de Política de Grupo aplicados*) e tente abrir o Painel de Controle.

**Opção 2 – sem VM cliente (somente laboratório, a que usamos)**: permita logon local dos operadores no próprio servidor. O script `scripts\Permitir-Logon-Operadores.ps1` faz os passos 1 a 3 por PowerShell (`Backup-GPO`, ajuste do direito `SeInteractiveLogonRight`, `Import-GPO`) e `.\Permitir-Logon-Operadores.ps1 -Remover` desfaz no passo 5. Pela interface:

1. `gpmc.msc` > Floresta > Domínios > citizentech.local > **Domain Controllers** > *Default Domain Controllers Policy* > Editar.
2. *Configuração do Computador > Políticas > Configurações do Windows > Configurações de Segurança > Políticas Locais > Atribuição de Direitos de Usuário* > **Permitir logon local**.
3. Adicione `CITIZENTECH\GG_CitizenTech_Operadores` **sem remover** as contas que já estão lá. OK.
4. `gpupdate /force`, saia da sessão e entre como `CITIZENTECH\carlos.lima` no console da VM.
5. Tente abrir o Painel de Controle e tire o print. Depois volte como Administrator e **remova** o grupo da política (boa prática de segurança).

### 5.2 Acesso remoto (RDP)

```powershell
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' -Name 'UserAuthentication' -Value 1
Enable-NetFirewallRule -Group '@FirewallAPI.dll,-28752'     # grupo "Área de Trabalho Remota", em qualquer idioma
```

Usamos RDP com NLA (autenticação antes de abrir a sessão). Não instalamos o Host de Sessão do RDS porque ele não é recomendado em um controlador de domínio e o roteiro aceita o RDP.

**Print** `04-ntfs-gpo/rdp-conexao.png`: no seu computador, `mstsc /v:192.168.200.230`, usuário `CITIZENTECH\Administrator`; na sessão remota abra o PowerShell e digite `hostname` (aparece `SRV-CITIZENTECH`).

### 5.3 DFS

```powershell
Install-WindowsFeature -Name FS-DFS-Namespace, FS-DFS-Replication -IncludeManagementTools
New-Item 'C:\DFSRoots\CitizenTechDFS' -ItemType Directory -Force
New-SmbShare -Name 'CitizenTechDFS' -Path 'C:\DFSRoots\CitizenTechDFS' -ReadAccess 'Everyone' -FullAccess 'BUILTIN\Administrators'
New-DfsnRoot   -Path '\\citizentech.local\CitizenTechDFS' -TargetPath '\\SRV-CITIZENTECH\CitizenTechDFS' -Type DomainV2
New-DfsnFolder -Path '\\citizentech.local\CitizenTechDFS\Documentos' -TargetPath '\\SRV-CITIZENTECH\CitizenTech'
Get-DfsnRoot
```

Em um namespace **de domínio** o caminho começa pelo nome do domínio e o destino precisa ser um compartilhamento (`\\servidor\share`), por isso criamos o compartilhamento `CitizenTechDFS` antes.

**Saída esperada**: raiz `\\citizentech.local\CitizenTechDFS`, `Type Domain V2`, `State Online`; a pasta `Documentos` mostra o mesmo conteúdo do compartilhamento.

**Print** `04-ntfs-gpo/get-dfsnroot.png`.

### 5.4 Auditoria e logs

**Script**

```powershell
.\06-Auditoria-Logs.ps1
```

**Comandos principais**

```powershell
# subcategorias pelo GUID (o nome "Logon" muda conforme o idioma; o GUID não)
auditpol /set "/subcategory:{0CCE9215-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable   # Logon
auditpol /set "/subcategory:{0CCE9216-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable   # Logoff
auditpol /set "/subcategory:{0CCE921D-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable   # Sistema de Arquivos
auditpol /set "/subcategory:{0CCE9235-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable   # Contas de usuário
auditpol /set "/subcategory:{0CCE9237-69AE-11D9-BED3-505054503030}" /success:enable /failure:enable   # Grupos de segurança
auditpol /get /category:*
Limit-EventLog -LogName Security -MaximumSize 256MB

# regra de auditoria (SACL) na pasta do site; o script faz o mesmo na pasta compartilhada
$pasta = Get-Item 'C:\inetpub\citizentech'
$acl = $pasta.GetAccessControl('Audit')
$regra = New-Object System.Security.AccessControl.FileSystemAuditRule('Everyone','ReadData, WriteData','ContainerInherit,ObjectInherit','None','Success,Failure')
$acl.AddAuditRule($regra)
$pasta.SetAccessControl($acl)     # NÃO use Set-Acl com um objeto lido só com 'Audit': ele zera as permissões (DACL nula)

Get-WinEvent -LogName Security -MaxEvents 20 | Select-Object TimeCreated, Id, Message
netsh http flush logbuffer                                  # força o IIS a gravar o log agora
Get-ChildItem 'C:\inetpub\logs\LogFiles' -Recurse | Select-Object FullName, Length
```

**Saída esperada**: subcategorias configuradas com sucesso e falha (*Success and Failure*); eventos 4624 (logon) e 4663 (acesso a arquivo) no log Security; arquivos `u_ex*.log` em `C:\inetpub\logs\LogFiles\W3SVC<n>`.

**Prints**: `07-logs/auditpol.png`, `07-logs/eventviewer-security.png` (`eventvwr.msc` > Logs do Windows > Segurança; filtre por 4624 e 4663) e `07-logs/iis-logs-pasta.png` (pasta `C:\inetpub\logs\LogFiles\W3SVC<n>` aberta no Explorador, com o `.log` aberto no Bloco de Notas se quiser).

---

## 4. Etapa 4 – Monitoramento com alertas (itens 6.1 a 6.3)

**Script**

```powershell
.\07-Monitoramento.ps1
```

### 6.1 Conjuntos de coletores de dados (Monitor de Desempenho)

São dois conjuntos, ambos visíveis em `perfmon` > *Conjuntos de Coletores de Dados > Definido pelo Usuário*:

```powershell
# 1) coleta: grava os três contadores a cada 15 s em CSV
logman create counter CitizenTech_Monitor -c "\Processor(_Total)\% Processor Time" "\Memory\Available MBytes" "\LogicalDisk(C:)\% Free Space" `
    -si 15 -f csv -v mmddhhmm -o C:\PerfLogs\CitizenTech\Recursos
logman start CitizenTech_Monitor

# 2) alerta nativo do perfmon: dispara quando passa do limite e grava no Visualizador de Eventos
logman create alert CitizenTech_Alertas -th "\Processor(_Total)\% Processor Time>80" "\Memory\Available MBytes<500" "\LogicalDisk(C:)\% Free Space<15" -si 15 -el
logman start CitizenTech_Alertas

logman query CitizenTech_Monitor
Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 2 -MaxSamples 3
```

No Windows em português os nomes dos contadores mudam (por exemplo, `\Processador(_Total)\% Tempo de Processador`) e o `logman` só aceita o nome no idioma instalado. O script descobre o nome certo sozinho (função `Get-ContadorLocal`) e salva a tradução em `05-monitoramento/contadores.txt`.

Cada disparo do alerta gera o **evento 2031** em *Logs de Aplicativos e Serviços > Microsoft > Windows > Diagnosis-PLA > Operacional*.

**Saída esperada**: `logman query` mostrando os dois conjuntos em execução (*Running*); arquivo `Recursos_<data>.csv` em `C:\PerfLogs\CitizenTech`; três leituras de CPU no `Get-Counter`.

**Prints**

- `05-monitoramento/perfmon-conjunto-ativo.png`: `perfmon` > Conjuntos de Coletores de Dados > Definido pelo Usuário, com `CitizenTech_Monitor` e `CitizenTech_Alertas` em execução (ícone verde).
- `05-monitoramento/perfmon-grafico.png`: `perfmon` > Ferramentas de Monitoramento > Monitor de Desempenho > botão **+** > adicione os três contadores: *Processor › % Processor Time (_Total)*, *Memory › Available MBytes* e *LogicalDisk › % Free Space (C:)* (em português: Processador, Memória e Disco Lógico, com os nomes equivalentes; os nomes exatos estão em `05-monitoramento/contadores.txt`). Para deixar o gráfico interessante, rode `C:\Scripts\Gerar-Carga.ps1` em outra janela.

### 6.2 Script de alerta por limiar

`C:\Scripts\Monitor-Recursos.ps1` ([código](../scripts/Monitor-Recursos.ps1)): mede CPU (média de 3 leituras), memória livre e disco livre por CIM (independe do idioma), grava o histórico em `C:\Scripts\logs\recursos.csv` e, se passar de um limite, grava em `alertas.log` e registra o **evento 9001** (Aviso) no log *Application*, origem `CitizenTechMonitor`.

```powershell
New-EventLog -LogName Application -Source 'CitizenTechMonitor'
powershell -ExecutionPolicy Bypass -File C:\Scripts\Monitor-Recursos.ps1
# demonstração dos três alertas com limiares artificiais (marcado como [SIMULACAO]):
C:\Scripts\Monitor-Recursos.ps1 -LimiteCPU -1 -LimiteRAM_MB 999999 -LimiteDisco_GB 99999 -Simulacao
# carga REAL de CPU (90 s) para ver o alerta de verdade:
C:\Scripts\Gerar-Carga.ps1
```

**Saída esperada**: linha verde com CPU, RAM livre e disco livre; ou linha amarela com o alerta.

**Prints**: `05-monitoramento/monitor-recursos.png` (execução no terminal) e `05-monitoramento/evento-alerta.png` (Visualizador de Eventos > Logs do Windows > Aplicativo, evento 9001 de `CitizenTechMonitor`, ou o evento 2031 do Diagnosis-PLA).

### 6.3 Agendar a verificação

```powershell
wevtutil set-log Microsoft-Windows-TaskScheduler/Operational /enabled:true   # liga o histórico do Agendador
$acao    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-NoProfile -ExecutionPolicy Bypass -File C:\Scripts\Monitor-Recursos.ps1'
$gatilho = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
$conta   = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName 'CitizenTech_Monitor_Alertas' -Action $acao -Trigger $gatilho -Principal $conta
Get-ScheduledTask -TaskName 'CitizenTech_Monitor_Alertas' | Select-Object TaskName, State
```

O script cria também `CitizenTech_Iniciar_Coletores`, que liga os dois conjuntos do perfmon a cada boot (eles não iniciam sozinhos depois de reiniciar).

**Saída esperada**: `State Ready` (ou `Running` durante a execução).

**Print** `05-monitoramento/agendador-tarefas.png`: `taskschd.msc` > Biblioteca do Agendador de Tarefas, com a tarefa selecionada e a aba **Histórico** mostrando execuções.

---

## 5. Etapa 5 – Teste de falha e recuperação automática (itens 7.1 a 7.3)

**Script** (itens 7.1 e 7.3)

```powershell
.\08-Tolerancia-Falhas.ps1
```

### 7.1 Recuperação automática do pool e do serviço

```powershell
Set-ItemProperty 'IIS:\AppPools\CitizenTechPool' -Name failure.rapidFailProtection -Value $false
Set-ItemProperty 'IIS:\AppPools\CitizenTechPool' -Name autoStart -Value $true
Set-ItemProperty 'IIS:\AppPools\CitizenTechPool' -Name startMode -Value 'AlwaysRunning'
sc.exe failure W3SVC reset= 86400 actions= restart/5000/restart/10000/restart/30000
sc.exe failure WAS   reset= 86400 actions= restart/5000/restart/10000/restart/30000
sc.exe qfailure W3SVC
```

**Saída esperada**: `RESET_PERIOD` de 86400 segundos e três ações de reinício (`RESTART`) com atraso de 5000, 10000 e 30000 ms.

**Prints**: `06-teste-falha/sc-qfailure.png` e `06-teste-falha/services-recuperacao.png` (`services.msc` > *Serviço de Publicação na World Wide Web* > Propriedades > aba **Recuperação**, com as três falhas em *Reiniciar o Serviço*).

### 7.3 Script de recuperação automática

`C:\Scripts\Recupera-Site.ps1` ([código](../scripts/Recupera-Site.ps1)), agendado a cada **1 minuto** como SYSTEM na tarefa `CitizenTech_Recuperacao`. Ordem: serviços WAS e W3SVC → pool → site → teste HTTP → `iisreset` se ainda falhar. Só escreve no `C:\Scripts\logs\recuperacao.log` quando precisou agir (cada linha é um incidente) e registra o evento 9101 no log Application.

### 7.2 Teste de falha

`C:\Scripts\Teste-Falha.ps1` ([código](../scripts/Teste-Falha.ps1)) segue as cinco etapas do roteiro e grava a saída em `C:\Scripts\logs\teste-falha-<cenario>-<data>.txt`.

| Cenário | Comando | O que acontece | Quem recupera | Tempo |
|---|---|---|---|---|
| Servico (roteiro) | `C:\Scripts\Teste-Falha.ps1` | `Stop-Service W3SVC` | tarefa `CitizenTech_Recuperacao` | até ~1 min |
| Crash | `C:\Scripts\Teste-Falha.ps1 -Cenario Crash` | encerra à força o processo do W3SVC (simula travamento) | Windows, pela aba Recuperação (`sc.exe failure`) | ~5 s |
| Pool | `C:\Scripts\Teste-Falha.ps1 -Cenario Pool` | `Stop-WebAppPool CitizenTechPool` (site responde 503) | tarefa `CitizenTech_Recuperacao` | até ~1 min |

Por que dois mecanismos: a aba Recuperação do Windows só age quando o serviço **cai sozinho**. Uma parada feita com `Stop-Service` é considerada intencional, então quem religa é a tarefa agendada. O cenário Crash prova a primeira camada; os cenários Servico e Pool provam a segunda.

**Saída esperada**: `[1]` W3SVC Running e HTTP 200 → `[2]` W3SVC Stopped (ou pool Stopped) → `[3]` *Site indisponível, como esperado* → `[4]` contagem até voltar → `[5]` W3SVC Running, HTTP 200 e *RESULTADO: recuperação AUTOMÁTICA em N segundos*. No fim aparecem os eventos 7031/7036 e as últimas linhas do `recuperacao.log`.

**Prints**

- `06-teste-falha/teste-falha-etapas.png`: as cinco etapas no terminal (cenário Servico ou Crash).
- `06-teste-falha/navegador-voltou.png`: navegador do seu computador recarregando `http://192.168.200.230` depois da recuperação.
- `06-teste-falha/recuperacao-log.png`: `Get-Content C:\Scripts\logs\recuperacao.log` depois dos cenários Servico e Pool.

---

## 6. Etapa 6 – Validação final e evidências (itens 8.1 a 8.3)

### 8.1 Comandos de validação final

```powershell
.\09-Validacao-Final.ps1
```

Executa o bloco do roteiro (`hostname`, `ipconfig /all`, `nslookup`, `Test-NetConnection -Port 80`, `Get-ADDomain`, `Get-WindowsFeature`, `Get-Website`, `Get-WebAppPoolState`, `Get-Service`, `Get-SmbShare`, `Get-GPO -All`) e grava `08-validacao-final/ficha-infraestrutura.txt`; um segundo bloco grava `validacao-extra.txt` (coletores, tarefas, recuperação, auditoria, DFS, usuários).

**Saída esperada**: `TcpTestSucceeded : True`, recursos `Installed`, site e pool `Started`, serviços `Running`.

**Print** `08-validacao-final/ficha-infraestrutura.png` (maximize a janela; se não couber, dois prints em sequência).

### Coletar as evidências

```powershell
.\10-Coletar-Evidencias.ps1
```

Copia para `evidencias\` os logs da operação (`alertas.log`, `recursos.csv`, `recuperacao.log`, saídas do teste de falha, amostra do CSV do perfmon, log do IIS, eventos), lista os prints que faltam e gera `C:\Temp\evidencias-citizentech.zip`.

### Levar as evidências para o repositório

- **Prints**: na VM, rode `.\Tirar-Print.ps1 <pasta>\<arquivo>.png -Atraso 5` e deixe a janela certa na frente; o PNG vai para `evidencias/<pasta>/` com o nome indicado em [evidencias/README.md](../evidencias/README.md). Prints do seu computador (navegador, Explorador, RDP): Win+Shift+S. Os links do README principal já apontam para esses nomes.
- **Saídas `.txt` e logs**: copie `C:\Temp\evidencias-citizentech.zip` para o seu computador (pasta compartilhada do hipervisor, arrastar e soltar ou upload no GitHub pelo navegador da VM em *Add file > Upload files*) e extraia na raiz do repositório (o .zip já contém a pasta `evidencias`; confirme a substituição dos arquivos).
- Faça o commit e o push. Confira no GitHub se os links da tabela de critérios abrem.

### 8.2 e 8.3 Estrutura e README

Prontos neste repositório: veja a [estrutura](../README.md#7-estrutura-do-repositório), a [Ficha da CitizenTech](../README.md#1-ficha-da-citizentech), a [tabela de critérios](../README.md#5-critérios-de-avaliação-e-evidências) e a [rastreabilidade](../README.md#6-rastreabilidade). Depois de executar, preencha os campos ✏️ do README (IP real, versão do Windows, hipervisor).

---

## 7. Caminho B – API AlertaEncosta (Java 21 / Spring Boot) no IIS · item 4.3

Além do portal (Caminho A), o servidor hospeda a **API REST do AlertaEncosta**, o backend da solução (repositório [`alertaencosta-api`](https://github.com/gustavoft2101/alertaencosta-api)). Ela roda no mesmo IIS, em um site e um pool próprios, e é vigiada pela mesma recuperação automática.

```powershell
# o .jar foi gerado no computador da equipe (mvn package no projeto alertaencosta-api, commit ffa835f)
# e o instalador do JDK 21 já estava baixado; os dois foram lidos da pasta compartilhada da VM
.\04b-IIS-API-Java.ps1 -JarPronto \\vboxsvr\Downloads\alertaencosta-api-1.0.0.jar
Copy-Item .\Recupera-Site.ps1 C:\Scripts\ -Force   # recuperação agendada passa a vigiar também a API
```

Sem parâmetros o script baixa o JDK (Eclipse Temurin), o Maven e o código da API e faz o build na própria VM. Na nossa VM a internet ficou lenta demais para isso (~80 KB/s), por isso usamos o `.jar` gerado no computador da equipe e instalamos o JDK com o instalador já baixado (`jdk-21_windows-x64_bin.exe /s INSTALLDIR=C:\Java\jdk21`, o mesmo que o parâmetro `-InstaladorJdk` faz).

O que o script faz:

| Passo | Comando principal | Resultado |
|---|---|---|
| Módulo do IIS | `msiexec /i httpPlatformHandler_amd64.msi` + `Install-WindowsFeature Web-AppInit` | O IIS passa a iniciar e vigiar o `java.exe` e repassar as requisições para ele |
| Runtime | JDK 21 em `C:\Java\jdk21` (instalador local ou Eclipse Temurin baixado) | `java -version` → 21.0.10 |
| Build | `.jar` pronto (`-JarPronto`) ou download do código + `mvn -DskipTests package` | `alertaencosta-api.jar` (57,6 MB) |
| Publicação | `C:\inetpub\alertaencosta-api\{app,data,logs}` + `web.config` | banco H2 em `data\`, saída do Java em `logs\` |
| Pool | `AlertaEncostaApiPool`: sem código gerenciado, `AlwaysRunning`, sem desligar por inatividade | a API sobe junto com o IIS |
| Site | `AlertaEncostaAPI`: porta **8080** e `api.citizentech.local` na porta 80 | `http://192.168.200.230:8080/swagger-ui.html` |
| Segurança | NTFS: só o pool da API grava em `data\` e `logs\`; console do H2 desligado; firewall só 8080 | |
| DNS | registro A `api.citizentech.local` → IP do servidor | |

`web.config` gerado (resumo):

```xml
<handlers>
  <add name="httpPlatformHandler" path="*" verb="*" modules="httpPlatformHandler" resourceType="Unspecified" />
</handlers>
<httpPlatform processPath="C:\Java\jdk21\bin\java.exe"
              arguments="-Xms128m -Xmx512m -jar C:\inetpub\alertaencosta-api\app\alertaencosta-api.jar
                         --server.port=%HTTP_PLATFORM_PORT%
                         --spring.datasource.url=jdbc:h2:file:C:/inetpub/alertaencosta-api/data/alertaencosta
                         --spring.h2.console.enabled=false"
              startupTimeLimit="180" startupRetryCount="3"
              stdoutLogEnabled="true" stdoutLogFile="C:\inetpub\alertaencosta-api\logs\java-stdout" />
```

Validação:

```powershell
Get-Website | Format-Table Name, State, PhysicalPath, ApplicationPool
Invoke-RestMethod http://localhost:8080/api/v1/setores | Select-Object -ExpandProperty conteudo |
    Format-Table codigo, nome, tipoRisco, nivelRiscoAtual
```

Saída esperada: sites `CitizenTech` e `AlertaEncostaAPI` em `Started` e os setores do piloto da Vila Brasilândia. No navegador de outra máquina: `http://192.168.200.230:8080/swagger-ui.html`.

Prints: `03-iis/api-get-website.png`, `03-iis/api-setores.png` e `03-iis/navegador-swagger.png`.

Teste de falha da API: `Stop-Process` no `java.exe` → o HttpPlatformHandler inicia outro `java.exe` na requisição seguinte e a API volta sozinha (no nosso teste, 44 s, quase todos de subida do Spring Boot com 1 vCPU). Print: `06-teste-falha/api-java-recuperado.png`.

---

## 8. Erros comuns e como resolver

| Problema | Causa provável | Solução |
|---|---|---|
| *"não pode ser carregado porque a execução de scripts foi desabilitada"* ou aviso de arquivo baixado | política de execução / marca de download | `Set-ExecutionPolicy -Scope Process Bypass -Force` e `Get-ChildItem C:\citizentech-infra -Recurse \| Unblock-File` |
| Script 01 diz que não há adaptador conectado | placa da VM desconectada ou Bridge sem rede | confira a rede da VM; em Wi-Fi use Host-only (item 0.2) |
| `New-NetIPAddress`: *Instance already exists* | IP antigo ainda na placa | o script remove antes; manualmente: `Remove-NetIPAddress -InterfaceIndex <n> -Confirm:$false` |
| `nslookup` falha ou mostra `UnKnown` | servidor não aponta para si mesmo / sem zona reversa | `Set-DnsClientServerAddress -InterfaceIndex <n> -ServerAddresses 192.168.200.230`; rode de novo o 03 (cria a zona reversa) |
| `Get-ADDomain`: *Unable to find a default server* logo após o boot | AD ainda iniciando | aguarde 1-2 minutos (o script 03 já espera) |
| Erro 500.19 no IIS | `web.config` inválido ou módulo ausente | confira o `web.config`; no Caminho B reinstale o Hosting Bundle/HttpPlatformHandler |
| Erro 401.3 | falta permissão NTFS para `IIS_IUSRS`/`IUSR` | rode de novo o 04 |
| Site não inicia (`State Stopped`) | outro site usando a porta 80 | `Get-Website`; remova/pare o *Default Web Site* |
| Site não abre pelo IP em outra máquina | firewall da porta 80 / rede | `New-NetFirewallRule -DisplayName 'HTTP' -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow`; teste `Test-NetConnection 192.168.200.230 -Port 80` no seu computador |
| `logman`: contador não encontrado | nome do contador no idioma errado | use o script 07 (traduz sozinho); confira `05-monitoramento/contadores.txt` |
| Coletores parados depois de reiniciar | perfmon não inicia conjuntos sozinho | a tarefa `CitizenTech_Iniciar_Coletores` resolve; manual: `logman start CitizenTech_Monitor` |
| Agendador sem histórico | histórico desligado por padrão | `wevtutil set-log Microsoft-Windows-TaskScheduler/Operational /enabled:true` (o 07 já faz) |
| Tarefa agendada não executa | conta ou privilégio errado | precisa ser SYSTEM com *Executar com privilégios mais altos*; `Get-ScheduledTaskInfo CitizenTech_Recuperacao` mostra o último resultado |
| Pool para sozinho depois de várias quedas | *Rapid-Fail Protection* | o 08 desliga (`failure.rapidFailProtection = False`) |
| Teste de falha não recupera em 30 s | `Stop-Service` não aciona a aba Recuperação | é esperado: a tarefa de 1 min religa; use `-Cenario Crash` para ver a recuperação do Windows em segundos |
| `Invoke-WebRequest`: erro do mecanismo do Internet Explorer | IE não inicializado | sempre use `-UseBasicParsing` |
| Usuário comum não consegue logon no servidor | controlador de domínio só permite administradores | veja as opções do item 5.1 (`scripts\Permitir-Logon-Operadores.ps1` faz a opção 2 e desfaz com `-Remover`) |
| Depois do script 06 o site dá erro 500.19 (código Win32 5) ou 401.3 e `icacls` mostra *No permissions are set* | versão antiga do 06 gravava a auditoria com `Set-Acl` e zerava a DACL | já corrigido (usa `SetAccessControl`); para reparar: `icacls C:\inetpub\citizentech /reset /T /C` e `icacls C:\Shares\CitizenTech /reset /T /C`, depois rode de novo 04, 05 e 06 |
| VM do VirtualBox congela 1-2 minutos de tempos em tempos; o log (*Máquina > Exibir Log*) mostra `fall back to NEM`, `TM: Giving up catch-up attempt` e `AHCI#0: Port 0 reset` | o Hyper-V está ativo no computador host e o VirtualBox roda sobre ele (modo NEM); com 2 vCPUs a VM trava esperando um processador pelo outro | foi o nosso caso: desligue a VM, deixe **1 vCPU** em *Configurações > Sistema > Processador* e ligue *Usar cache de E/S do hospedeiro* em *Armazenamento > Controladora SATA* |
