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

## Dock modular, widgets e feedback real — 0.6.0

Referências do usuário: duas imagens de Dock com aplicativos e blocos funcionais; uma de desktop com grandes relógios, barras discretas e conteúdo sem cartão. A direção foi implementada com os serviços existentes: música, timer, bateria, notas e indicadores reais. As imagens não justificaram inventar dados de clima, bolsa, temperatura, fan ou copiar assets.

Dock: rail contínuo ou tiles separados; modelos/medidas comuns para os dois eixos, opção/ordem de módulos, presets explícitos e nota local. O timer mostra uma duração configurável antes de iniciar, com play, seleção de presets e atualização numérica finita. Demanda agrega aos serviços compartilhados e exige painel visível/revelado. Presets mantêm apps, notas, monitores e estado ligado/desligado.

Widgets: Card/Glass/Desktop, fonte/peso/tinta/cantos/cabeçalho e presets por item; relógio Desktop até 200 pt, data/fuso e mínimo 72 pt nos indicadores. Conteúdo real, snapshots internos do relógio 620×250 e bateria compacta/black foram inspecionados. O último usa sRGB 0,0,0 opaco; branco legível, cabeçalho suprimido no compacto e editável em edição. Native appearance e colorScheme são explícitos, e sizingOptions vazio preserva a geometria AppKit.

A captura física do usuário comprovou um defeito: preferir dark em SwiftUI não bastava para o campo nativo dentro de um container. A Island e a Dock agora resolvem darkAqua/aqua na janela e também no ambiente da view. Um teste lê o campo NSTextField real e verifica texto claro; a captura interna da calculadora foi inspecionada com labels/entrada/resultado legíveis. A altura da calculadora agora 225 pt em modo adaptativo, limitada pela preferência de tamanho e com alternativa fixa.

Pointer exit: o foco comum da calculadora/nota não impede mais o recolhimento indefinidamente. Marcação IME, menus/child windows, pin e ponteiro real continuam protegidos. A Dock limpa foco/hover visual ao recolher; a atualização ativa auto-hide uma vez, preservando escolhas posteriores. Tests nativos exercitaram composição marcada e commit antes de recolher a 10 pt.

Em monitor sem recorte, o cap compacto tem exatamente a altura da barra medida; o corpo recolhido é zero e não desenha borda abaixo. Quando a barra está escondida, usa NSStatusBar.thickness como fallback. O MacBook físico mantém sua borda 4 pt e o mesmo desenho de ombros.

Bluetooth: listener Classic de eventos públicos, baseline silencioso e ledger de reconexão. Aviso de 4 s com símbolo/nome/status, sem tomar teclado e sem iniciar dados de módulos; evento durante edição mantém campo/conteúdo. Testes de UI alimentam eventos explicitamente e nunca iniciam hardware. Não há leitura de bateria privada, scan, pairing ou garantia para BLE-only/lid-open.

Replace macOS Dock: opção explícita e global de auto-hide por System Events, com verificação, restauração e journal próprio de melhor esforço.31 verificações com adaptador isolado passaram sem mudar a Dock real. O primeiro método de encerramento terminateLater bloqueou um Task MainActor num loop aninhado (confirmado por sample temporário); foi substituído por cancelamento inicial, restauração assíncrona e nova solicitação aprovada. Sem restauração pendente, encerra imediatamente. Falha real permite cancelar saída ou sair mantendo dados de recuperação. A Dock nativa continua podendo aparecer na borda.

A nova logo fornecida pelo Claude foi inspecionada e empacotada em ICNS; a UI e o ícone em execução selecionam variante por aparência, Finder estático no macOS 14. Cache/deduplicação do MusicService foram revisados e integrados a partir do trabalho do Claude, com validação de serviços.

Qualidade/profiling: mantivemos SwiftUI/AppKit e filas de trabalho, sem backend Rust ou timer de 120 Hz. O framework adapta a animação ao refresh; a seção Performance mostra capacidade, não FPS observado. True Tone é uma adaptação de tela do macOS e não foi alterado. Não se declara 120 FPS/perfeição/QA físico a partir de build/snapshots. A coordenação com Claude usou a skill [orchestration](/Users/uemuradev/.agents/skills/orchestration/SKILL.md); resultados de microbenchmark têm escopo próprio em PERFORMANCE.md.

Fechamento 0.6.0: builds Debug e Release passaram; 27 testes do núcleo e 98 condições da rotina Debug passaram. Smokes services, Dock, dock-motion, widgets, widget-motion, Bluetooth e native-dock passaram. O relógio mínimo 220×72 foi inspecionado após ajustar escala/espaçamento. O encerramento de widgets tem fallback finito para callbacks de animação em janelas ocluídas. AppleScript de música e Dock compartilham fila serial, evitando execução OSA concorrente. Na execução final os painéis Dock estavam ocluídos: foi verificada suspensão, sem alegar observação positiva de demanda visível nesse ambiente. Ativação global de teclado foi negada pelo macOS; os bindings/campos internos foram testados. [Evidência e limitações](Validation/2026-11-09-workspace.json).

Reabertura real detectou um bloqueio que os testes sem hardware não cobriam: registerForConnectNotifications aguardava um semáforo de CoreBluetooth na main thread durante launch. Sample temporário confirmou a pilha. O transporte agora serializa registro/callbacks/teardown numa fila utility; gerações descartam eventos tardios. Avisos são opt-in por padrão. Não se declara a conexão física validada com essa correção; a inicialização normal e saída são verificadas separadamente.

Após a correção Bluetooth, Debug/Release, núcleo (27), smoke Bluetooth sem hardware e rotina nativa (98) passaram novamente. A instância Release abriu via LaunchServices com ambiente limpo, informou isFinishedLaunching=true, encerrou normalmente por NSRunningApplication.terminate e teve saída confirmada antes da reabertura final.

## Compact Island and player connection — 0.6.1

Problem: the user still had a roughly503×489pt saved panel. Shrinking defaults alone would leave it huge. A one-time migration caps existing expansion at360×260 and preserves position, modules, content and subsequent manual choices. Invalid stored settings are not overwritten. Compact/Minimal presets are smaller than Default. The duplicate title row was removed; navigation/pin/collapse share one line, with finite WorkspaceMotion transitions and Reduce Motion handling.

Internal snapshot review found remaining blank space below music controls after the first210pt attempt. Connected music was reduced again to170pt and disconnected music150pt. Actual native captures show selector,40pt artwork, transport, volume, seek/times at300×170; a long test title truncates with tooltip. Disconnected guidance fits360×150. Calculator input/result/copy/history/status remain legible at360×195. Long YouTube instructions are in a native Browser setup popover, cleared on player/connection changes and disappearance. These are internal captures, not external typing/hover/FPS certification.

Connection: desktop Connect now launches an installed player when closed; generation checks discard an old launch response after switching/disconnecting. Choice persists in injected preferences; without a choice a running Spotify is preferred. Nothing requests Automation on startup. YouTube Chrome/Safari/Brave and YouTube Music use explicit local browser automation, exact hosts, normalized JSON, and skip tabs without video. Player scripts and browser scripts compiled against installed dictionaries;66 JavaScriptCore fixture/compile checks and service smoke passed without executing browser/player Apple Events. A disconnected browser may need its own JavaScript-from-Apple-Events setting, and autoplay/DOM changes remain real limitations. No live playback claim is made.

Final Debug/Release builds,27 core tests and the native Debug runtime passed. The runtime exercises actual300pt connected controls using an explicitly marked Debug-only local script fixture; this proves layout/bindings, not Spotify or YouTube playback. See [report](Validation/2026-11-09-compact-music.json) for actual check count and permission/focus limits.

## Reference-shaped notch overview — 0.7.0

The five new user images clarified the problem: the opening should be a shallow, horizontal notch surface rather than the detailed module editor. Hover/click now enters a560×140pt music/calendar overview; Tools opens the existing compact editor and Back returns without losing calculation/timer state. The detailed size preference remains intact and overview-first can be disabled. Native pin/collapse, permission actions and player selection remain available. Disabled modules are respected.

Compact playback adds44pt wings outside each side of the measured camera center. Artwork and playing/paused state come from the authorized MusicService; position-only updates do not republish the cap projection. The waveform is a static play-state symbol, not measured amplitude or decorative animation. Geometry tests cover invalid extension, shifted screen origins and physical/synthetic cameras; both connected displays retain their collapsed menu-band height.

Public CoreAudio/IOPS callbacks provide silent-baseline, deduplicated output-change/Mac-low-battery notices. A first native run caught a real regression: applying settings dismissed a system notice when the separate Bluetooth toggle was off. Source identity now selects the correct toggle, and the repeat passed. Short banners are340×60pt for4s and do not request keyboard. AirPods battery/noise control, camera mirror and global Focus are not implemented or simulated.

Native screenshot judgment: music/calendar hierarchy, divider, week/date, Controls/Tools/pin/collapse and camera-centered wings are legible and proportioned like the supplied references. Empty, connected-layout and wings use explicit Debug-only local fixtures/no authorization to real players. One initial cached empty-state render was incomplete; a repeated run produced the complete layout. Cache helpers now flush pending native layout/display before state capture. This certifies internal final-state screenshots, not physical animation timing.

Motion uses shared finite WorkspaceMotion timings, Reduce Motion and interruption reconciliation. Runtime tests exercise overview→editor→overview, preserved calculation/focus intent, hover and repeated reversal, per-display cap geometry, short event banners and disabled sources. System-notice smoke uses30 pure checks and never starts hardware listeners. No live AirPods/output-change/battery-discharge, external typing/hover, VoiceOver or achieved FPS claim is made. Final counts/builds are recorded in [report](Validation/2026-11-09-notch-overview.json).

## Notch hover intent and native Dock repair — 0.7.1

Reference: [boring.notch](https://github.com/TheBoredTeam/boring.notch) (GPL-3.0), studied for observable behavior only (README, sizing/hover constants read as facts). No code, assets, MediaRemote, private CGS spaces or XPC helper were copied or adopted.

**Comparison, judged rather than claimed equivalent.** boring.notch closes to the real notch size (width = notch + 4 pt), opens to 640×190 pt, uses springs (open ≈0.42/0.8, close ≈0.45/1.0), opens on hover after a configurable minimum dwell, closes ~100 ms after exit and reads Now Playing through a MediaRemote adapter. BetterApple 0.7 opened instantly on any pointer contact, held a hover peek for the full 1.5 s close delay, painted a 4 pt lip below the hardware notch and kept 12 pt concave shoulders. Problems: (1) sweeping across the menu bar to a nearby menu flashed the overview; (2) leaving a peek felt sticky; (3) the collapsed silhouette was visibly larger than the camera housing; (4) Release could never show calendar events because the hardened runtime lacked the Calendars entitlement (tccd: “requires entitlement com.apple.security.personal-information.calendars but it is missing”, denied without prompt).

**Changes.** 0.15 s hover intent (`WorkspaceMotion.hoverIntent`) — click remains immediate, Reduce Motion does not alter intent. Hover-revealed overview closes within 0.3 s (`hoverExitGrace`) or the user’s shorter close delay; deliberately opened overview/tools keep the configured delay (preference preserved, 0 still keeps open). Close deadlines inside NSMenu tracking are deferred and rearmed by `NSMenu.didEndTracking` (latent bug for every delay, made likelier by the faster exit). Collapsed camera cap paints only the safe-area band; the 4 pt seam overlap remains as an invisible hover margin. Kept deliberately: 12 pt shoulders (discoverability, no width jump during expansion), 560×140 overview (content fits, verified in capture), AppKit cubic window timing instead of springs (NSWindow frames are AppKit-owned; no spring overshoot of real windows), static playback symbol instead of fake spectrum, no haptics/gesture swipe (not requested; trackpad-only).

**Evidence (internal, not physical).** Runtime `--validate` 120/120 including new checks: sweep shorter than intent does not open; hover peek closes after exit despite a 5 s delay (guarded by real pointer location); deliberate overview stays open past 0.45 s; painted inset equals seam on camera display. Capture alpha scan: built-in cap window 74 px (37 pt) → 66 opaque px (33 pt = safe-area top), bottom 4 pt transparent; LG ULTRAWIDE cap 30 pt fully painted = measured menu bar; centre pixel sRGB 0,0,0. These calls drive the same handler as tracking-area hover; physical pointer feel, timing perception, VoiceOver and FPS were not measured.

**Replace macOS Dock — root cause.** The real Release prefs never stored `nativeDock.replacementWanted`; unified logs showed System Events reading autohide (`GetBooleanPreference preference=3`) after each toggle but never writing. NSAppleScript returns AppleScript booleans as `typeTrue`/`typeFalse` (verified: `return autohide of dock preferences` → `'fals'`), while the adapter accepted only `typeBoolean`, so every real reply threw “System Events returned an unexpected Dock setting”. Fake-adapter checks bypassed the parser. Fixed parser plus a smoke check over real local NSAppleScript descriptors (fails on old code). Real controlled run of the actual `NativeDockService`/`SystemEventsNativeDockAccess` (terminal’s Automation identity, isolated journal suite): baseline autohide 0 → enable 0.13 s → autohide 1, LG ULTRAWIDE bottom reserve 87 pt → 0, built-in 0 → 0 → restore → autohide 0, reserve 87 pt, journal cleared. The supported mechanism is auto-hide: the native Dock still reveals at the screen edge, and with both Docks at the bottom edge the pointer can reveal both. Not tested: the toggle clicked inside the rebuilt Release app — ad-hoc signing changes the code hash, so macOS may ask for Automation again and that click must be human.
