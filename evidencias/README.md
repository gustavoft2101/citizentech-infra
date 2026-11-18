# Evidências

Dois tipos de arquivo ficam nesta pasta:

- 📄 **`.txt`, `.log`, `.csv`, `.html`** – gerados automaticamente pelos scripts na VM (mesma saída mostrada na tela). Vêm no `C:\Temp\evidencias-citizentech.zip` criado pelo `10-Coletar-Evidencias.ps1`.
- 🖼️ **`.png`** – prints tirados pela equipe. Salve **com exatamente estes nomes** para os links do README funcionarem.

Como tiramos os prints: dentro da VM, `Z:\scripts\Tirar-Print.ps1 <pasta>\<arquivo>.png -Atraso 5` salva a tela inteira do servidor em `evidencias\` depois de 5 segundos (tempo de deixar a janela certa na frente). Os prints que mostram o **seu computador** (navegador, Explorador, RDP) saem com Win+Shift+S.

## Checklist de prints

| ✔ | Arquivo | O que precisa aparecer | Roteiro | Critério |
|---|---|---|---|---|
| ✅ | `01-rede/winver.png` | Área de trabalho do Windows Server com a janela do `winver` mostrando a versão | 3.1 | Rede e identidade |
| ✅ | `01-rede/ipconfig-all.png` | `ipconfig /all` com hostname, IP, máscara, gateway e DNS visíveis | 3.2 | Rede e identidade |
| ✅ | `02-ad-dns/get-addomain.png` | Saída do `Get-ADDomain` (citizentech.local) | 3.4 | Rede e identidade |
| ✅ | `02-ad-dns/nslookup.png` | `nslookup srv-citizentech.citizentech.local` resolvendo para o IP do servidor | 3.4 | Rede e identidade |
| ✅ | `02-ad-dns/get-dnsserverzone.png` | Zona `citizentech.local` como Primary | 3.4 | Rede e identidade |
| ✅ | `02-ad-dns/usuarios-grupos.png` | `Get-ADUser ... -SearchBase "OU=CitizenTech,..."` e `Get-ADGroupMember` | 3.5 | Rede e identidade |
| ✅ | `03-iis/get-windowsfeature-web.png` | Recursos `Web-*` instalados | 4.1 | Aplicação no IIS |
| ✅ | `03-iis/get-website.png` | Site CitizenTech `Started`, caminho e pool | 4.2 | Aplicação no IIS |
| ✅ | `03-iis/get-webapppoolstate.png` | `Get-WebAppPoolState` Started e `Invoke-WebRequest` StatusCode 200 | 4.2 | Aplicação no IIS |
| ✅ | `03-iis/navegador-site.png` | Navegador de OUTRA máquina em `http://<IP>` com o AlertaEncosta e o rodapé "Servido por SRV-CITIZENTECH" | 4.2 | Aplicação no IIS |
| ✅ | `03-iis/get-acl.png` | `Get-Acl` com IIS_IUSRS ReadAndExecute Allow | 4.4 | Aplicação no IIS |
| ✅ | `03-iis/aba-seguranca.png` | Propriedades de `C:\inetpub\citizentech` > Segurança, IIS_IUSRS selecionado | 4.4 | Aplicação no IIS |
| ✅ | `04-ntfs-gpo/get-smbshare.png` | `Get-SmbShare` com o compartilhamento CitizenTech | 4.5 | Aplicação no IIS |
| ✅ | `04-ntfs-gpo/acesso-share-cliente.png` | Explorador de Arquivos de outra máquina em `\\<IP>\CitizenTech` | 4.5 | Aplicação no IIS |
| ✅ | `04-ntfs-gpo/get-gpo-all.png` | `Get-GPO -All` com GPO_CitizenTech_Usuarios | 5.1 | Funcionamento completo |
| ✅ | `04-ntfs-gpo/usuario-sem-painel.png` | Usuário comum (carlos.lima) recebendo a restrição ao abrir o Painel de Controle | 5.1 | Funcionamento completo |
| extra | `04-ntfs-gpo/gpresult-carlos.png` | `gpresult /r /scope user` do carlos.lima com a GPO_CitizenTech_Usuarios aplicada | 5.1 | Funcionamento completo |
| ✅ | `04-ntfs-gpo/rdp-conexao.png` | Sessão RDP a partir de outra máquina com `hostname` digitado no terminal remoto | 5.2 | Funcionamento completo |
| ✅ | `04-ntfs-gpo/get-dfsnroot.png` | `Get-DfsnRoot` com `\\citizentech.local\CitizenTechDFS` Online | 5.3 | Funcionamento completo |
| ✅ | `05-monitoramento/perfmon-conjunto-ativo.png` | perfmon > Conjuntos de Coletores > Definido pelo Usuário: CitizenTech_Monitor e CitizenTech_Alertas em execução | 6.1 | Monitoramento |
| ✅ | `05-monitoramento/perfmon-grafico.png` | Monitor de Desempenho com os 3 contadores (CPU, memória, disco) no gráfico | 6.1 | Monitoramento |
| ✅ | `05-monitoramento/monitor-recursos.png` | Execução do `Monitor-Recursos.ps1` no terminal (linha verde ou amarela) | 6.2 | Monitoramento |
| ✅ | `05-monitoramento/evento-alerta.png` | Visualizador de Eventos com o evento 9001 (CitizenTechMonitor) ou 2031 (Diagnosis-PLA) | 6.2 | Monitoramento |
| ✅ | `05-monitoramento/agendador-tarefas.png` | Agendador de Tarefas com CitizenTech_Monitor_Alertas e a aba Histórico | 6.3 | Monitoramento |
| ✅ | `06-teste-falha/sc-qfailure.png` | `sc.exe qfailure W3SVC` com RESET_PERIOD e os 3 RESTART | 7.1 | Tolerância a falhas |
| ✅ | `06-teste-falha/services-recuperacao.png` | services.msc > W3SVC > aba Recuperação | 7.1 | Tolerância a falhas |
| ✅ | `06-teste-falha/teste-falha-etapas.png` | As 5 etapas do `Teste-Falha.ps1` no terminal | 7.2 | Tolerância a falhas |
| extra | `06-teste-falha/navegador-falha.png` | Navegador do computador da equipe durante a queda: selo vermelho "Servidor sem resposta" | 7.2 | Tolerância a falhas |
| ✅ | `06-teste-falha/navegador-voltou.png` | Navegador carregando o site de novo após a recuperação | 7.2 | Tolerância a falhas |
| ✅ | `06-teste-falha/recuperacao-log.png` | Conteúdo do `C:\Scripts\logs\recuperacao.log` após o teste | 7.3 | Tolerância a falhas |
| ✅ | `07-logs/auditpol.png` | `auditpol /get /category:*` com Logon e Sistema de Arquivos em sucesso e falha | 5.4 | Logs e auditoria |
| ✅ | `07-logs/eventviewer-security.png` | Visualizador de Eventos > Segurança (eventos 4624 / 4663) | 5.4 | Logs e auditoria |
| ✅ | `07-logs/iis-logs-pasta.png` | Pasta `C:\inetpub\logs\LogFiles\W3SVC<n>` aberta | 5.4 | Logs e auditoria |
| ✅ | `08-validacao-final/ficha-infraestrutura.png` | Saída completa do `09-Validacao-Final.ps1` | 8.1 | Funcionamento completo |
| extra | `08-validacao-final/ficha-infraestrutura-extra.png` | Segunda tela do `09` (coletores, tarefas, recuperação, auditoria, DFS, usuários) | 8.1 | Funcionamento completo |

## Arquivos gerados pelos scripts

| Pasta | Arquivos | Gerado por |
|---|---|---|
| `01-rede` | `versao-windows.txt`, `get-netadapter.txt`, `ip-fixo-aplicado.txt`, `ipconfig-all.txt` | 01, 03 |
| `02-ad-dns` | `install-adds.txt`, `install-addsforest.txt`, `dns-encaminhadores.txt`, `get-addomain.txt`, `nslookup.txt`, `get-dnsserverzone.txt`, `usuarios.txt`, `grupos.txt` | 02, 03 |
| `03-iis` | `install-iis.txt`, `get-windowsfeature-web.txt`, `arquivos-site.txt`, `get-acl.txt`, `get-website.txt`, `get-webapppoolstate.txt`, `invoke-webrequest.txt` | 04 |
| `04-ntfs-gpo` | `get-smbshare.txt`, `gpo.txt`, `GPO_Report.html`, `rdp.txt`, `dfs.txt` | 05 |
| `05-monitoramento` | `contadores.txt`, `logman-query.txt`, `get-counter.txt`, `monitor-recursos-execucao.txt`, `monitor-recursos-simulacao.txt`, `tarefas-agendadas.txt`, `eventos-alerta.txt`, `alertas.log`, `recursos.csv`, `perflogs-amostra.csv` | 07, 10 |
| `06-teste-falha` | `pool-configuracao.txt`, `sc-qfailure.txt`, `recupera-site-execucao.txt`, `recuperacao.log`, `teste-falha-*.txt`, `eventos-servico.txt` | 08, Teste-Falha, 10 |
| `07-logs` | `auditpol.txt`, `sacl.txt`, `eventos-security.txt`, `eventos-security.csv`, `iis-logs.txt`, `iis-log-amostra.txt`, `iis-u_ex*.log` | 06, 10 |
| `08-validacao-final` | `ficha-infraestrutura.txt`, `validacao-extra.txt` | 09 |

As linhas marcadas com `[SIMULACAO]` no `alertas.log` vêm da demonstração com limiares artificiais (`-Simulacao`); as demais são alertas reais.
