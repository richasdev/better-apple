# Progresso e próximos passos

Legenda: `[x]` código integrado e verificação indicada; `[ ]` pendente, parcial ou não validado.

## Fase 1 — Fundação

- [x] Projeto Xcode macOS 14+, Swift Package, menu bar e janela de configurações.
- [x] Configurações locais, validação de JSON e presets.
- [x] Roundtrip JSON real da suíte e rejeição de versão inválida sem alterar o estado, verificados na rotina interna.
- [x] Atalho global opcional configurável; registro, conflito, liberação e persistência verificados em harness.
- [x] Repositório privado e commits separados por área.
- [x] Builds reais SPM, Xcode Debug e Xcode Release em Apple silicon.
- [x] Sete testes do núcleo sem falhas.
- [ ] Definir licença de distribuição, marcas, assinatura e notarização.

## Fase 2 — Dynamic Island

- [x] NSPanel, hover/clique, recolhimento, Reduce Motion, geometria e seleção/ordem de módulos.
- [x] Calculadora com parser seguro, cópia e testes.
- [x] Calendário EventKit com solicitação explícita e tratamento de negativa.
- [x] Timer com pausa, retomada, conclusão e reconciliação após sleep.
- [x] Validação interna executou expansão/recolhimento, cálculo e conclusão real de timer.
- [ ] Validar concessão/revogação do calendário com dados reais; não foi solicitado acesso durante o desenvolvimento automatizado.
- [ ] Verificar manualmente hover, foco de campos, áreas de menu, Spaces e tela cheia em macOS 14/15.
- [ ] Histórico opcional de calculadora.

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
- [ ] Instâncias simultâneas em vários monitores, temas próprios além dos presets de tamanho/opacidade.

## Fase 5 — Widgets

- [x] Dez tipos com conteúdos/serviços reais e sem valores demonstrativos.
- [x] Visibilidade individual, tamanhos/posições persistidos, modo de edição, temas/cores, bordas e sombras.
- [x] Validação interna criou todos os tipos, alterou notas e confirmou liberação de demanda ao ocultar.
- [ ] Validar manualmente arraste, resize, retorno entre Spaces, teclado e layouts após desconectar monitores.
- [ ] Seleção granular de informações por widget; hoje cada tipo define seu conteúdo.

## Fase 6 — Otimização e qualidade

- [x] Demanda por visibilidade/oclusão, suspensão em sleep, observadores removidos e polling limitado.
- [x] Release compilado e medição inicial documentada em PERFORMANCE.md.
- [ ] Perfis prolongados Allocations/Leaks, cenários de música e múltiplos widgets.
- [ ] Validar 60 FPS, Reduce Motion e VoiceOver interativamente.
- [x] Build Release universal compilou arm64 e x86_64.
- [ ] Execução em macOS 14/15 e Intel; build no SDK atual não comprova execução nesses sistemas.
- [ ] Tornar importação da suíte tolerante a versões futuras com migrações explícitas.

## Limitação da validação visual

O helper de Computer Use do Orca retornou `permission_denied` para Accessibility ao inspecionar o processo, inclusive após informar permissão concedida. Nenhuma interação externa foi declarada aprovada. Uma repetição inicial confundiu expansão com demanda visível quando havia outra instância aberta; o harness foi corrigido para verificar a geometria real da janela e executado isoladamente. A rotina Debug `--validate` usa os próprios managers e NSViews, sem essa permissão, e passou onze verificações. Capturas internas de NSView têm limitações de composição (materiais/alguns conteúdos podem ficar escuros ou vazios) e não substituem captura real e QA manual.
