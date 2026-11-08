# Revisão contínua de UI/UX e movimento

Esta revisão aplica o pedido do usuário de julgar cada alteração durante implementação e teste. “Perfeita” não é uma conclusão técnica: comportamento observado, inspeção, captura interna e interação física são evidências diferentes. O procedimento está registrado em [AGENTS.md](AGENTS.md).

## Direção da versão 0.3.0

Movimento discreto, responsivo e finito. Feedback de controles em 120 ms, conteúdo em até 180 ms, transições de superfície em torno de 220–280 ms, respeitando a duração pessoal da Island/Dock. Expansão desacelera; fechamento é mais curto. Não há efeitos decorativos repetitivos ou novos timers globais. Reduce Motion remove movimento espacial e atrasos; Reduce Transparency mantém superfícies opacas.

## Problema → alteração → julgamento

| Área | Problema observado/revisado | Alteração | Evidência e limite |
|---|---|---|---|
| Island | Conteúdo trocado de uma vez durante resize; fechamento/reabertura podiam deixar callbacks antigos | Coreografia finita de janela/conteúdo, invalidação por geração e reconciliação final | Teste nativo de reversões e edição durante resize terminou em geometria compacta exata |
| Entrada e foco | Esperar a revelação para montar o campo podia perder entrada; pedido antigo podia acompanhar outro módulo/tela | Campo montado no início, pedido explícito direcionado ao painel e ao módulo, limpeza ao abrir Settings/perder key | Editor nativo e binding preparados durante expansão; entrega física de teclas depende da ativação concedida pelo macOS |
| Hover e recolhimento | Tracking areas mudam durante resize; editor/popover aberto não deve desaparecer | Ponteiro real conferido no deadline, pin/edição protegidos, política reagendada por eventos | Pin, hover sem pedido de ativação, deadline e movimento desativado exercitados; mouse físico ainda não certificado |
| Dock | Ampliação oscilava ao entrar na área ampliada; vizinhos/labels podiam sobrepor | Posição contínua do ponteiro, slots estáveis, deslocamento dos vizinhos e métricas compartilhadas | Harness verificou limites com ícones 80 px, escala 1.5×, labels, reversão e auto-hide |
| Tamanho das janelas | Conteúdo SwiftUI retido impedia a Dock de voltar a 10 px | `NSHostingView.sizingOptions = []` nas superfícies cuja geometria pertence ao AppKit | Falha reproduzida e teste repetido até confirmar dimensão real de 10 px; Island também mantém dimensão compacta |
| Widgets | Movimentos bruscos, frames intermediários persistidos e callbacks antigos de hide | Animações finitas, supressão de persistência intermediária, fechamento por identidade/geração | Harness moveu/retargetou, ocultou/reexibiu rapidamente e preservou nota e hosting view |
| Edição de desktop | Handles mudavam o header; widgets cobertos continuavam inacessíveis; overflow sobrepunha layout | Header estável, controles maiores, edição traz widgets à frente e organização rejeita overflow sem alterar posições | Estado/layout e overflow verificados; gestos de mouse ainda dependem de QA externo |
| Conteúdo pequeno | Música, eventos e timer cortados em widgets mínimos | Contenção com rolagem, feedback e controles com alvos maiores | Compilação e cenários nativos cobrem tamanhos; clipping visual precisa de inspeção interativa |
| Calculadora/timer | Erros mudavam a altura; campo numérico inválido reutilizava valor antigo | Status com espaço reservado, feedback de cópia, drafts textuais validados e submit explícito | Casos vazios, inválidos, limites e decimal pt-BR verificados sem iniciar um timer antigo |
| Música/calendário | Seek de faixas de mesmo título podia ficar obsoleto; evento de dia inteiro mostrava hora; data podia ficar em ontem | Identidade mais completa, confirmação de seek limitada, labels de dia inteiro e refresh de data por eventos | Código compilado e casos de validação exercitados; comandos dos players e dados pessoais não foram acionados |
| Settings | Navegação e presets sem feedback consistente; avisos discretos demais | Transição breve, hover/press nos presets, seção lembrada durante a sessão, erro com dismiss | Inspeção e compilação; navegação real por teclado/VoiceOver não certificada |
| Erro fora das Settings | Falha ao abrir app na Dock só aparecia nas configurações | Aviso nativo sem ativação automática, ação para a seção Dock, pausa do deadline durante interação | Capacidade de key e teardown nativo verificados; não se presume que Tab/VoiceOver físico tenha sido exercitado |

## Ciclos de julgamento e correções

1. Revisão inicial dividida por superfície e revisão cruzada de código. Problemas de hover, foco, clipping e perda de layout foram tratados antes de ampliar efeitos.
2. O teste estendido descobriu o mínimo do hosting view impedindo auto-hide real. O teste só passou depois da correção da geometria.
3. A revisão detectou risco de recursão quando não há monitores; o rebuild agora encerra sem recriar indefinidamente e aguarda um evento de display.
4. Testes de foco inicialmente falharam porque exigiam `isKey` num contexto que o macOS não ativava. Probes AppKit diretos e via LaunchServices distinguiram a negativa de ativação da preparação real do editor. O gate foi corrigido para intenção explícita por painel, sem ativar a aplicação no hover ou mudar a policy de produção.
5. A validação passou a registrar ativação não concedida como limitação, testar separadamente o editor/binding e sair com código não zero em falha real. Artefatos antigos são removidos antes da execução para não reutilizar um PASS anterior.

A [Apple documenta que a ativação é uma solicitação dependente do contexto desde macOS 14](https://developer.apple.com/documentation/macos-release-notes/appkit-release-notes-for-macos-14). Os testes não alteram permissões nem forçam a aplicação ativa a entregar foco.

## Critérios mantidos em aberto

- Mouse/trackpad físico, Tab e VoiceOver entre aplicações e Spaces.
- Inspeção visual completa em claro/escuro, escalas e monitores diferentes. Capturas internas podem omitir composição de materiais.
- FPS e hitches sob carga real; medir uma sequência não equivale a comprovar 60 FPS universais.
- Allocations/Leaks por períodos prolongados e uso comum com múltiplos widgets.

Resultados consolidados e medições da versão ficam em `Validation/2026-11-08-motion.json` e [PERFORMANCE.md](PERFORMANCE.md). Esses limites impedem afirmar uma certificação visual perfeita; não substituem os testes executados.
