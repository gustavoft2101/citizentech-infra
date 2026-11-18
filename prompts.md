# Registro de uso de IA (prompts.md)

Combinado da GS: *"IA como copiloto – permitida para aprender e revisar. Registrem os prompts em um arquivo prompts.md e saibam explicar cada linha."*

Ferramenta usada: **Claude (Anthropic)**, com acesso à tela do computador da equipe (VirtualBox, navegador e Explorador de Arquivos).

| # | Data | Prompt | O que a IA fez | O que a equipe fez e como validou |
|---|---|---|---|---|
| 1 | 17/11/2026 | "Preciso que faça para mim isso de operating system", com o roteiro da atividade, o briefing da GS e a arquitetura do AlertaEncosta em anexo | Estrutura do repositório, scripts PowerShell comentados das etapas 1 a 6, `Monitor-Recursos.ps1`, `Teste-Falha.ps1`, `Recupera-Site.ps1`, portal estático com dados simulados, README e documentação | Leitura dos scripts e do README antes de executar |
| 2 | 17/11/2026 | "Me ajude com passo a passo para deixar tudo no jeito para a entrega" | Passo a passo de criação da VM e de execução dos scripts | Conferência com o roteiro da atividade |
| 3 | 17 e 18/11/2026 | "Você não pode fazer tudo isso por mim? (...) só para quando precisar que eu faça algo" | Criou o repositório no GitHub, criou a VM no VirtualBox, instalou o Windows Server, executou os scripts 01 a 10 e os testes de falha na VM, tirou os prints e enviou os arquivos ao GitHub | Instalou o VirtualBox, digitou todas as senhas (Administrator, DSRM, usuários de teste), fez os logins (inclusive como `carlos.lima` para o teste da GPO), abriu o site e a pasta compartilhada no próprio computador e conectou por RDP para os prints de "outra máquina"; conferiu os prints |
| 4 | 18/11/2026 | Correções durante a execução (sem prompt novo: problemas encontrados na VM) | Corrigiu o script 06, que apagava as permissões NTFS ao gravar a auditoria (site com erro 500.19); corrigiu o erro HTTP 406 do portal no Firefox; diagnosticou os congelamentos da VM (VirtualBox sobre Hyper-V) e reduziu para 1 vCPU | Repetiu os testes: site respondendo HTTP 200 e queda/recuperação vista no navegador |

## Senhas e dados pessoais

- Nenhuma senha foi digitada pela IA nem está no repositório: todas foram digitadas pela equipe na hora da execução.
- Os prints tirados no computador da equipe foram recortados para não mostrar abas, contas ou pastas pessoais.

## Pontos para saber explicar na apresentação

- Por que o pool é "sem código gerenciado" (site estático, evita o erro 500.19).
- Diferença entre permissão de compartilhamento (SMB) e permissão NTFS (vale a mais restritiva).
- Por que o `sc.exe failure` não age num `Stop-Service` e quem recupera nesse caso (tarefa agendada).
- Por que usamos SIDs e GUIDs (Windows em português x inglês).
- O que são os eventos 9001, 9101, 2031, 4624, 4663 e 7031/7036.
- Por que gravar a auditoria com `SetAccessControl` e não com `Set-Acl` (o `Set-Acl` zerou as permissões da pasta).
