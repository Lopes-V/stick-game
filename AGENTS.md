# Chaos Stick Arena — Agent Guide

## Objetivo

Este repositório contém um arena fighter 2D local pela rede LAN, feito em Godot 4.x e GDScript. Um host executa o servidor dedicado authoritative e serve a build Web; de dois a quatro navegadores entram na mesma arena. Não adicionar multiplayer público, contas, banco de dados ou dependências obrigatórias externas.

## Prioridades

Preservar, nesta ordem: inicialização, movimento responsivo, combate e knockback, quatro jogadores, Void Loop, mapa The Core, armas, rounds e Chaos. Estabilidade da física e jogabilidade têm prioridade sobre cosméticos.

## Arquitetura

- `scripts/core/`: `GameManager`, `RoundManager`, câmera, impacto, Void Loop e configuração.
- `scripts/network/`: servidor/cliente WebSocket High-Level Multiplayer e snapshots.
- `scripts/player/`: jogador authoritative e coleta de input do cliente.
- `scripts/weapons/`: catálogo, armas físicas, projéteis e spawner.
- `scripts/map/`: arena procedural e props/barrels físicos.
- `scripts/chaos/`: `ChaosDirector`, base `ChaosEvent` e eventos modulares.
- `scripts/ui/`: lobby, HUD e debug para teclado e mouse.
- `tools/`: servidor HTTP LAN sem dependências e smoke test.

O cliente envia input, nunca posição, dano, KO, spawn, score ou evento Chaos. O servidor executa a física a 60 Hz e publica snapshots a 30 Hz. Atualizações com `teleport_serial` devem ser aplicadas com snap, sem interpolar através da arena.

## Void Loop

Cruzar o limite inferior teleporta jogadores, armas, caixas, barris, rockets e granadas para uma posição segura no céu. Preserve velocidades horizontal e vertical dentro dos limites seguros, arma segurada, impacto e knockback. Respeite cooldown por corpo, impeça múltiplos wraps no mesmo frame e nunca faça objetos destruídos retornarem.

## Chaos

Somente o servidor executa `ChaosDirector` e seu RNG. Eventos devem implementar `start_event`, `update_event`, `stop_event` e compatibilidade. Todo modificador precisa ser restaurado no fim do evento e no reset do round. Chaos aumenta risco e força o movimento, mas deve sempre sinalizar perigos evitáveis.

## Como executar e validar

Abra `project.godot` na Godot 4.x e use F6/F5 para cliente nativo. Servidor dedicado:

```text
godot --headless --path . -- --server
```

Smoke test:

```text
godot --headless --path . -- --server --test-bots=4 --auto-start --smoke-test --seed=424242
```

Para o fluxo LAN completo, execute `HOST_GAME.bat` no Windows ou `./host_game.sh` no Linux. Antes de enviar mudanças, rode importação headless, smoke test e, quando afetar Web/UI, a build Web e uma verificação em navegador.

## Convenções

Use GDScript tipado quando razoável, indentação com tab conforme `gdformat`/Godot, nomes claros e funções curtas. Coloque testes perto do sistema ou em `tools/`. Não editar arquivos gerados em `.godot/`. Não adicionar plugins, assets externos ou bibliotecas de terceiros sem necessidade explícita. Formas procedurais e recursos nativos são o padrão visual.
