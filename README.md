# Chaos Stick Arena

Arena fighter 2D para 2–4 jogadores na mesma rede local. O host roda uma simulação authoritative em Godot; os demais jogadores abrem um link no navegador, entram no lobby e jogam sem instalar o projeto. Todo visual atual é procedural e usa formas nativas da Godot.

## Requisitos

- No Windows, o launcher já inclui o runtime portátil Godot 4.7.1; não é
  necessário instalar a Godot nem configurar `PATH`/`GODOT_EXE` para hospedar.
- Python 3 apenas para o servidor HTTP do launcher LAN.
- Para editar o projeto, use Godot 4.x. Para refazer `web_build/`, também são
  necessários os templates oficiais de exportação Web.
- Navegador com WebAssembly/WebGL 2 para cada jogador.

Não há plugins, pacotes, assets ou serviços externos obrigatórios.

## Como executar

Fluxo recomendado no Windows:

1. Dê duplo clique em `HOST_GAME.bat`.
2. O launcher valida a build Web, inicia o servidor Godot headless na porta `9000`, inicia HTTP na `8080` e só então mostra `ONLINE`.
3. O navegador do host abre `http://localhost:8080`.
4. Envie o link `http://IP_DA_LAN:8080` mostrado na tela para 1–3 pessoas na mesma rede.
5. Todos informam o nome, marcam `READY`, e o primeiro navegador (host da sala) usa `START GAME`.

Linux: torne os scripts executáveis e rode `./host_game.sh`. Também é possível abrir `project.godot` no editor e pressionar F6/F5 para testar um cliente nativo enquanto um servidor está ativo.

Servidor manual:

```text
godot --headless --path . -- --server
python tools/lan_http_server.py --directory web_build --port 8080
```

O cliente Web deriva o WebSocket de `window.location.hostname`; não existe IP hardcoded. As portas, limite de jogadores, início do Chaos e pontuação ficam em `server_config.json`.

O launcher prepara a exportação **sem threads** para funcionar por HTTP dentro
da rede privada, sem instalar certificados em cada celular. Controles touch,
teclado e mouse funcionam nesse modo. Alguns navegadores restringem a Gamepad
API em HTTP; nesses casos use os controles touch/teclado ou configure HTTPS.
Como `AudioWorklet` também exige HTTPS, a build LAN usa automaticamente o
driver de áudio Dummy. Isso não remove nenhum som atual, pois o protótipo ainda
não depende de arquivos de áudio.

## Build Web

No Windows, execute `BUILD_WEB.bat`; no Linux, `./build_web.sh`. Ambos usam o preset `Web` de `export_presets.cfg` e geram `web_build/index.html` e os arquivos `.js`, `.wasm` e `.pck` correspondentes.

## Controles

Teclado e mouse:

- `A` / `D`: mover.
- `W` ou `Space`: pular.
- Mouse: mirar.
- Clique esquerdo ou `J`: atacar/disparar.
- Clique direito ou `K`: arremessar arma.
- `E`: pegar/trocar arma.

Gamepad:

- Left Stick: mover.
- A/Cross: pular.
- X/Square: atacar.
- B/Circle: arremessar.
- Y/Triangle: pegar.
- Right Stick: mirar.

Celulares exibem joysticks de movimento/mira e botões touch; use o aparelho em paisagem.

Ferramentas do host: `F1` adiciona dummy, `F2` faz chover uma arma, `F3` inicia Chaos, `F4` força o próximo evento, `F5` reinicia o round e `F10` alterna o overlay de debug.

## Mecânicas

Impact começa em 0% e aumenta com socos, tiros, explosões, objetos e body slams. O percentual multiplica knockback; KO é determinístico e exige Impact alto combinado com um golpe relevante.

As sete armas-base são pistol, shotgun, rifle, sniper, rocket launcher, katana e grenade launcher. Armas soltas têm física, atravessam o Void Loop e causam impacto quando arremessadas. Golden Gun e Cursed Shotgun aparecem raramente no Chaos.

No Void Loop, cruzar a parte inferior conecta o corpo ao céu sem respawn: velocidade, Impact e arma são preservados com limites seguros e cooldown. Jogadores podem voltar em body slam; rockets, granadas, armas, caixas e barris também usam o loop.

Após 30 segundos, o Core inicia Chaos e escala até o nível MAX. O diretor authoritative combina eventos modulares como Low/High Gravity, Super Knockback, Wind, Flying Objects, Weapon Rain, Gravity Pulse, Explosive Rain, Blackout, Moving Platforms, Core Shockwave, Floor Panic, Ammo Overload e Mirror Projectiles.

O último jogador vivo marca um ponto. A arena, modificadores, objetos temporários, projéteis e eventos são limpos entre rounds. O primeiro a cinco pontos vence a partida.

## Estrutura

- `scenes/main/`: cena inicial única.
- `scripts/core/`: ciclo da partida, rounds, câmera e Void Loop.
- `scripts/network/`: lobby, IDs, RPC de input e snapshots.
- `scripts/player/`, `scripts/weapons/`, `scripts/map/`: simulação authoritative.
- `scripts/chaos/events/`: eventos independentes e reversíveis.
- `scripts/ui/`, `scripts/effects/`: apresentação local não-authoritative.
- `tools/`: HTTP LAN e validação automatizada.

## Rede e firewall

O HTTP usa `8080/TCP`; o jogo WebSocket usa `9000/TCP`. O launcher não altera o Windows Firewall. Caso outro aparelho não conecte, confirme que ambos estão na mesma rede, que a rede do Windows está como privada e permita manualmente a Godot/Python ou essas duas portas. Redes de convidados podem bloquear comunicação entre dispositivos.

## Validação rápida

```text
godot --headless --editor --path . --quit
godot --headless --path . -- --server --test-bots=4 --auto-start --smoke-test --seed=424242
```

O smoke test valida os quatro jogadores e seus inputs, pickup, tiro/munição, arremesso, Void Loop de jogador/objeto, pelo menos oito eventos modulares, KO, score, próximo round e reset authoritative.
