# BetterApple 0.7.1 — primeira pré-release

Publicação de testes para macOS 14 ou superior, universal (`arm64` e `x86_64`). Build 11. O número acompanha a versão existente do produto; esta é sua primeira publicação no GitHub Releases.

## Conteúdo

- Dynamic Island com overview horizontal, música, calendário, calculadora e timer.
- Dock personalizada, widgets e preferências/notas locais preservadas.
- Correções de hover do notch, permissão de calendário e leitura do auto-hide da Dock nativa.
- Ajustes da Dock já presentes no workspace: ícones sem placa permanente, feedback durante drag, magnificação com curva cossenoidal e animações compartilhadas de tracking/retorno. Saída usa 75% da duração de entrada; duração zero e Reduce Motion desativam as animações de tracking.

## Instalação e assinatura

Baixe `BetterApple-0.7.1-universal-macos.zip`, extraia e mova `BetterApple.app` para Applications. Abra pelo Finder e procure seu ícone na barra de menus. O arquivo `SHA256SUMS.txt` permite conferir a integridade do ZIP.

O pacote tem assinatura **Apple Development: Ricardo Uemura**, hardened runtime e timestamp. Não está assinado com **Developer ID Application** e não está notarizado. `codesign --verify --all-architectures --deep --strict` passou no bundle original e no ZIP extraído. A avaliação `spctl --assess --type execute` rejeitou o app. Portanto esta publicação não oferece a experiência de instalação de um app notarizado e não é uma release estável.

O macOS pode bloquear a abertura. Se você confiar na origem, use System Settings → Privacy & Security → Open Anyway, quando oferecido pelo sistema. Não desative o Gatekeeper.

## Limitações

- Integrações reais com Calendar, players/navegadores e Bluetooth dependem de autorização e ambiente; os testes automatizados não certificam todas essas interações físicas.
- YouTube exige configuração explícita de JavaScript from Apple Events no navegador e pode mudar com o site.
- Replace macOS Dock usa auto-hide suportado; a Dock nativa continua podendo aparecer na borda.
- Não há certificação de FPS, VoiceOver ou fluidez percebida com ponteiro físico.
- Licença e revisão do nome/marcas para distribuição estável continuam pendentes. Não há concessão de licença de redistribuição/modificação.

## Preparação do pacote

Build Release universal pelo Xcode, assinatura local com certificado Apple Development disponível e entitlements de `Resources/BetterApple.entitlements`, ZIP criado com `ditto --sequesterRsrc --keepParent`. O certificado Developer ID necessário à distribuição notarizada não está disponível neste Mac.

Os resultados desta publicação são registrados em `Validation/2026-11-09-first-release.json` e `UX_REVIEW.md`.
