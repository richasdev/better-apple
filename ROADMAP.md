# Progresso e próximos passos

Legenda: `[x]` código integrado e verificação indicada; `[ ]` pendente, parcial ou não validado.

## Fase 1 — Fundação

- [x] Projeto Xcode macOS 14+, Swift Package, menu bar e janela de configurações.
- [x] Configurações locais, validação de JSON e presets.
- [x] Roundtrip JSON real da suíte e rejeição de versão inválida sem alterar o estado, verificados na rotina interna.
- [x] Atalho global opcional configurável; registro, conflito, liberação e persistência verificados em harness.
- [x] Repositório privado e commits separados por área.
- [x] Builds reais SPM, Xcode Debug e Xcode Release em Apple silicon.
- [x] 25 testes do núcleo sem falhas, incluindo temas/presets e histórico de cálculo.
- [ ] Definir licença de distribuição, marcas, assinatura e notarização.

## Fase 2 — Dynamic Island

- [x] NSPanel, hover/clique, recolhimento, Reduce Motion, geometria e seleção/ordem de módulos.
- [x] Calculadora com parser seguro, cópia e testes.
- [x] Calendário EventKit com solicitação explícita e tratamento de negativa.
- [x] Timer com pausa, retomada, conclusão e reconciliação após sleep.
- [x] Validação interna executou expansão/recolhimento, cálculo e conclusão real de timer.
- [ ] Validar concessão/revogação do calendário com dados reais; não foi solicitado acesso durante o desenvolvimento automatizado.
- [ ] Verificar manualmente hover, foco de campos, áreas de menu, Spaces e tela cheia em macOS 14/15.
- [x] Histórico opcional de calculadora com limite, limpeza e reutilização.

## Fase 3 — Música

- [x] Adaptadores injetáveis Music/Spotify usando Apple Events públicos.
- [x] Controles, volume, seek, metadados e artwork opcional; autorização e player ausente tratados.
- [x] Harness verificou ausência de conexão implícita e registro de adaptador adicional.
- [ ] Exercitar ambos os players, diálogos de Automation e todos os comandos com reprodução real.

## Fase 4 — Dock

- [x] Aplicativos reais resolvidos por bundle ID, abertura e indicadores via NSWorkspace.
- [x] Drag-and-drop interno com validação, rolagem para overflow e ícones em cache.
- [x] Posição, monitor selecionável, auto-hide, magnificação, materiais e configurações.
- [x] Validação interna confirmou resolução de aplicativos reais.
- [ ] Validar arraste/reordenação/hover manualmente e com várias telas físicas.
- [x] Instâncias simultâneas da Dock por monitor e personalização de material, tema, cor e magnificação; smoke validou a contagem nas telas conectadas.
- [ ] Validar comportamento em múltiplos monitores físicos diferentes.

## Fase 5 — Widgets

- [x] Dez tipos com conteúdos/serviços reais e sem valores demonstrativos.
- [x] Visibilidade individual, tamanhos/posições persistidos, modo de edição, temas/cores, bordas e sombras.
- [x] Validação interna criou todos os tipos, alterou notas e confirmou liberação de demanda ao ocultar.
- [ ] Validar manualmente arraste, resize, retorno entre Spaces, teclado e layouts após desconectar monitores.
- [x] Seleção granular de informações por tipo, fontes, títulos e fusos horários.
- [x] Duplicação, organização e snap ao arrastar pelo handle ou terminar resize.

## Fase 6 — Otimização e qualidade

- [x] Demanda por visibilidade/oclusão, suspensão em sleep, observadores removidos e polling limitado.
- [x] Release compilado e medição inicial documentada em PERFORMANCE.md.
- [ ] Perfis prolongados Allocations/Leaks, cenários de música e múltiplos widgets.
- [ ] Validar 60 FPS, Reduce Motion e VoiceOver interativamente.
- [x] Build Release universal compilou arm64 e x86_64.
- [ ] Execução em macOS 14/15 e Intel; build no SDK atual não comprova execução nesses sistemas.
- [ ] Tornar importação da suíte tolerante a versões futuras com migrações explícitas.

## Limitação da validação visual

O helper de Computer Use do Orca retornou `permission_denied` para Accessibility ao inspecionar o processo, inclusive após informar permissão concedida. Nenhuma interação externa foi declarada aprovada. Uma repetição inicial confundiu expansão com demanda visível quando havia outra instância aberta; o harness foi corrigido para verificar a geometria real da janela e executado isoladamente. A rotina Debug `--validate` usa os próprios managers e NSViews, sem essa permissão, e passou 46 verificações internas na versão 0.4, com limitações de ativação registradas separadamente. Capturas internas de NSView têm limitações de composição (materiais/alguns conteúdos podem ficar escuros ou vazios) e não substituem captura real e QA manual.

## Evolução 0.2.0

- [x] Temas da Island, materiais, cor, borda/sombra/cantos e animação configuráveis; Reduce Transparency respeitado.
- [x] Pin da Island, status compacto opcional e atualizações visuais sem recriar a janela.
- [x] Presets determinísticos e identificação de aparência Custom após ajustes manuais.
- [x] Timer com rótulo, presets, progresso, alerta configurável, extensão e reinício.
- [x] Importação das preferências antigas verificada na suíte integrada, preservando notas.
- [x] Quatro harnesses nativos de serviços, produtividade, Dock e widgets executados.
- [ ] QA visual/interativo continua limitado pela permissão do helper de Computer Use.

## Evolução 0.3.0 — revisão e movimento

- [x] Sistema compartilhado de feedback/movimento finito e invariantes de acessibilidade testados.
- [x] Coreografia da Island, retarget/reversão, preparação antecipada do editor e intenção de foco por painel/módulo.
- [x] Magnificação contínua e recolhimento real da Dock a 10 px, verificados em harness estendido.
- [x] Animações de widgets sem persistir frames intermediários; retenção de notas/hosting view e overflow seguro.
- [x] Validação textual e decimal local do timer; feedback consistente, controles maiores e estados vazios/erros revisados.
- [x] Procedimento permanente de julgamento em AGENTS.md e UX_REVIEW.md.
- [x] Seis harnesses nativos executados, além de 15 testes do núcleo e 32 verificações integradas.
- [x] Captura Animation Hitches de 15 s concluída em sequência finita de 20 ciclos.
- [ ] A captura não trouxe amostras de frames utilizáveis: FPS/ausência de hitches permanecem não certificados.
- [ ] Ativação real e entrega de teclas entre aplicações/Spaces, mouse/trackpad e VoiceOver continuam sujeitos a QA interativo.

## Câmera / notch — 0.4

- [x] Geometria pura com coordenadas globais, gap validado, telas sem notch, telas pequenas e medidas inválidas.
- [x] Cap estreito sem key, corpo abaixo dos menus, expansão para baixo e hover compartilhado.
- [x] Modo Camera aplicado uma vez às preferências existentes; Floating e aparência mantidos.
- [x] Regressão para diferença entre safe area de 32 pt e barra visível de 33 pt neste Mac.
- [ ] Verificação física do ponteiro, composição visual do recorte, Spaces e fullscreen em diferentes MacBooks.

## Seleção de recursos — 0.4.1

- [x] Três switches independentes em General e controles equivalentes no menu bar.
- [x] Widgets com ativação persistente, separada do repouso e da visibilidade individual.
- [x] Desmontagem de janelas/conteúdo ao desligar e restauração de notas/layout ao religar.
- [x] Exportação/importação das escolhas e compatibilidade com JSON antigo.
- [x] Conteúdo SwiftUI de novos widgets montado de fato; regressão verificada por hierarquia nativa.
- [x] 62 verificações internas passaram em duas execuções consecutivas; 25 testes de núcleo passaram.
- [ ] Conferir switches e composição dos widgets com mouse/VoiceOver e refazer profiling com conteúdos reais.
