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

## Integração com câmera — 0.4.0

Problema: a Island aparecia como uma janela abaixo da barra, distante da câmera. Uma expansão larga sobre a barra também poderia interceptar comandos dos menus.

Alteração: cap preto estreito no gap físico medido, corpo separado abaixo da faixa reservada pelo sistema e uma borda compacta de 4 pt. Hover mantém o cap estável e expande o corpo para baixo, com as transições finitas existentes e Reduce Motion. Camera desativa dados compactos; Floating preserva toda a aparência anterior. Na falta de notch, faixa de 80 × 8 pt abaixo da barra.

Julgamento e correções: revisão independente identificou que clique após hover não deveria recolher e que migração automática não poderia sobrescrever JSON incompatível; ambos corrigidos. O teste nativo revelou safe area de 32 pt e barra efetiva de 33 pt neste Mac. A geometria agora respeita o maior limite, evitando o deslocamento automático de 1 pt pelo AppKit. A origem horizontal compacta foi alinhada pelo AppKit de 659,5 a 659 pt; a comparação admite menos de 1 pt, mantendo dimensões exatas.

Evidência: 25 testes do núcleo passaram. Builds Debug arm64 e Release universal passaram. As 46 verificações internas passaram em duas execuções isoladas consecutivas, incluindo cap sem key, hover sem pedido de ativação, transição cap→corpo, clique idempotente, recolhimento e preservação de dados. Uma execução enquanto o Release compilava falhou na antiga asserção de reversão rápida; as duas repetições sem compilação concorrente passaram. Isso permanece registrado como sensibilidade do teste temporal sob carga, sem atribuir uma causa definitiva.

Geometria real observada: tela 1512 × 982 pt; corpo compacto 193 × 4 pt, topo em 949 pt; expandido 440 × 340 pt no mesmo topo; cap de 185 × 37 pt. Não houve acesso à câmera. [Relatório desta etapa](Validation/2026-11-09-camera.json).

Limites: geometria e estado de NSWindow não certificam composição física do notch, mouse/trackpad, Spaces, fullscreen ou 60 FPS. Nenhuma nova medição de CPU/RAM foi feita. Acesso externo à UI continua indisponível neste ambiente.

## Seleção independente de recursos — 0.4.1

Problema: General tinha controles para Island/Dock, mas o controle de Widgets era somente edição de layout. Não existia uma escolha persistente de desligar o recurso inteiro, independente de repouso e visibilidade de cada widget.

Alteração: três switches nativos em General, cada um com descrição e acesso à configuração; os mesmos recursos têm marcas no menu bar. Desligar preserva notas/layout/aplicativos e desmonta as janelas, incluindo widgets em fade. Edição fica indisponível com Widgets desligado. Não há animação contínua nem nova permissão; navegação e controles usam a linguagem nativa existente.

Julgamento: o teste de conteúdo montado revelou um bug anterior: NSPanel já cria uma NSView vazia, logo a verificação contentView == nil não instalava o hosting de novos widgets. A criação agora instala NSHostingView explicitamente. O teste verifica a hierarquia real, além do estado persistido.

A regressão de reversão rápida da Island voltou a falhar e uma tentativa de substituir o alvo do animator com duração zero causou um ciclo de constraints; essa tentativa foi removida. A evidência nativa apontou resize animado do próprio NSHostingView competindo com a geometria AppKit. O hosting da Island agora vive num NSView com autoresizing, deixando a janela sob controle do AppKit. Duas execuções completas consecutivas passaram após a correção, incluindo a dimensão compacta de 34 pt, abertura do editor e geometria Camera.

Evidência desta etapa: 25 testes do núcleo sem falhas e 62 verificações internas em duas execuções consecutivas. Cobertura nova: três recursos independentes, janelas reais, notas/posições/visibilidade individual, importação/exportação, escolha persistida, retomada de repouso sem reativação e desligamento durante fade/reversões. Não se declara validação física dos switches, VoiceOver, composição visual nem FPS. Não foram medidas CPU/RAM novamente após montar os conteúdos reais dos widgets.

A captura interna de General foi inspecionada: as três linhas, descrições, switches e atalhos de configuração formam uma hierarquia legível na área central. A captura de NSView não compõe corretamente alguns materiais/cores da sidebar; ela não certifica a aparência final no monitor. [Relatório de verificações](Validation/2026-11-09-features.json).

O harness widget-motion também passou após fortalecer a regressão: host SwiftUI real e manager/id corretos, nota exibida no NSTextView nativo, edição via insertText propagada ao modelo, nova instância do host ao reexibir com a mesma nota e movimentos sem persistir frames intermediários. Isso valida editor/binding internos, sem afirmar entrega física de teclado.

## Revisão de conceitos e configuração — 0.4.2

Problemas: a pergunta do usuário revelou ambiguidade entre recorte físico, posição da janela e cobertura de monitores. Camera mostrava numerosos controles desativados que só fazem sentido em Floating. A Dock misturava posição e comportamento e seus números não tinham unidades.

Alterações: Displays agora explicita câmera/monitor automático ou todos, fallback sem notch e expansão/módulo compartilhados. Controles exclusivos de Floating ficam ocultos no modo Camera, preservando valores. A Dock separa Placement/Behavior/Appearance/Motion e apresenta pt, %, × e s, incluindo valores de acessibilidade. Não foram adicionadas transições, timers ou permissões; switches e pickers continuam nativos.

A revisão identificou que editar apps fixados com a Dock desligada podia deixar a lista de metadados obsoleta. Mudanças na lista e abertura das Settings agora a atualizam por evento, sem criar janelas. O carregamento inicial já existia e não foi tratado como uma falha de startup.

Julgamento: preferimos explicar o efeito e mostrar apenas ajustes aplicáveis, mantendo o modo flutuante disponível para liberdade visual. A configuração de todos os monitores ainda compartilha aparência e estado, sem perfis independentes por tela. O recorte físico não é desenhável: cap estreito no gap medido e borda abaixo integram o conteúdo à câmera. Não se certifica composição visual, gesto físico, VoiceOver ou FPS pela compilação e estado de janelas.

Validação: build Debug e 64 verificações internas passaram, incluindo criação de uma Island por tela conectada e expansão compartilhada. Smoke nativo da Dock passou com edição de metadados desligada, preferências e bytes persistidos preservados e zero janelas. Na primeira execução combinada, a contagem de widgets incluiu uma nota com alpha zero ainda em retirada de um caso anterior; o novo fixture agora desmonta esses painéis antes de iniciar sua contagem independente. As verificações multi-display já passaram nessa execução inicial. Nenhuma medição nova de CPU/RAM/FPS. [Relatório](Validation/2026-11-09-settings-review.json).

## Silhueta Notchy em todas as telas — 0.5.0

Referência fornecida pelo usuário: imagem anexada e [short enviado](https://www.youtube.com/shorts/ZMaE1vlID-s). A imagem define o contorno: preto, topo preso à borda, ombros côncavos e base arredondada. O acesso ao YouTube retornou metadados, sem frames reproduzíveis; a análise visual usou a imagem anexada. Nenhum código/asset do aplicativo de referência foi copiado.

Problema: a faixa de 80 × 8 pt em monitor comum e o cap estreito fixo não reproduziam a forma solicitada. A expansão tinha um corpo visualmente separado, com cantos superiores arredondados.

Alteração: a mesma silhueta aparece em toda tela. No MacBook, o gap físico calibra centro/largura. Sem recorte ou sem medidas auxiliares válidas, um notch visual de 185 pt usa faixa mínima de 32 pt, encostado ao topo. O cap inclui ombros côncavos de 12 pt e acompanha a largura do corpo, com sobreposição preta de 4 pt; o corpo tem topo reto e base arredondada. A área central dos menus é coberta deliberadamente pela silhueta, conforme a referência.

Movimento: cap e corpo usam o mesmo NSAnimationContext, curva e duração pessoal, com expansão desacelerada e fechamento mais curto. Reduce Motion/zero duração mantêm reconciliação imediata. O cap também recebeu container NSView para evitar o resize automático do hosting. A regressão de reversão rápida do modo Floating ainda falhou inicialmente por alvo antigo do animator; a reconciliação imediata agora substitui esse alvo nas duas janelas, usando os containers isolados. As verificações da nova geometria já passavam antes dessa correção.

Julgamento visual: o smoke novo renderiza o CameraCapView e o corpo nativos em fundo claro. O PNG temporário foi inspecionado: ombros côncavos, contorno compacto e união expandida contínua sem costura no raster. Paths reais testam canto interno/externo, raio, coordenadas deslocadas, tamanhos pequenos e sobreposição. Esse raster é um diagnóstico offscreen, não captura física sobre a barra de menus.

Evidência: 26 testes do núcleo e smoke notch-shape passaram. A rotina nativa completa passou duas vezes consecutivas após a correção do animator; a última execução verificou 74 condições, incluindo cap e corpo reais após reversões, hover bidirecional, identidade, edição de largura e todas as telas conectadas. [Relatório](Validation/2026-11-09-notchy.json).
