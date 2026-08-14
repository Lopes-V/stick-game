import fs from 'node:fs';
import path from 'node:path';

const outputDirectory = path.resolve(process.argv[2] ?? 'test-results/browser');
fs.mkdirSync(outputDirectory, { recursive: true });

const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

class CdpPage {
  constructor(port, label) {
    this.port = port;
    this.label = label;
    this.nextId = 1;
    this.pending = new Map();
    this.exceptions = [];
    this.consoleErrors = [];
    this.webSockets = [];
    this.webSocketFramesReceived = 0;
    this.webSocketFramesSent = 0;
  }

  async connect() {
    let target;
    for (let attempt = 0; attempt < 40; attempt += 1) {
      const targets = await fetch(`http://127.0.0.1:${this.port}/json/list`).then((response) => response.json());
      target = targets.find((entry) => entry.type === 'page');
      if (target) break;
      await delay(250);
    }
    if (!target) throw new Error(`${this.label}: Edge page target was not found`);
    this.socket = new WebSocket(target.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error(`${this.label}: CDP connection timed out`)), 5000);
      this.socket.addEventListener('open', () => {
        clearTimeout(timeout);
        resolve();
      }, { once: true });
      this.socket.addEventListener('error', reject, { once: true });
    });
    this.socket.addEventListener('message', (event) => this.onMessage(JSON.parse(String(event.data))));
    await Promise.all([
      this.send('Page.enable'),
      this.send('Runtime.enable'),
      this.send('Network.enable'),
      this.send('Log.enable'),
    ]);
	await this.send('Emulation.setDeviceMetricsOverride', {
		width: 1280,
		height: 720,
		deviceScaleFactor: 1,
		mobile: false,
	});
	if (!target.url.includes('127.0.0.1:8080')) {
		await this.send('Page.navigate', { url: 'http://127.0.0.1:8080' });
	}
  }

  onMessage(message) {
    if (message.id && this.pending.has(message.id)) {
      const { resolve, reject, timeout } = this.pending.get(message.id);
      clearTimeout(timeout);
      this.pending.delete(message.id);
      if (message.error) reject(new Error(message.error.message));
      else resolve(message.result ?? {});
      return;
    }
    if (message.method === 'Runtime.exceptionThrown') {
      this.exceptions.push(message.params.exceptionDetails.text ?? 'Runtime exception');
    } else if (message.method === 'Log.entryAdded' && message.params.entry.level === 'error') {
      this.consoleErrors.push(message.params.entry.text);
    } else if (message.method === 'Network.webSocketCreated') {
      this.webSockets.push(message.params.url);
    } else if (message.method === 'Network.webSocketFrameReceived') {
      this.webSocketFramesReceived += 1;
    } else if (message.method === 'Network.webSocketFrameSent') {
      this.webSocketFramesSent += 1;
    }
  }

  send(method, params = {}) {
    const id = this.nextId++;
    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`${this.label}: ${method} timed out`));
      }, 10000);
      this.pending.set(id, { resolve, reject, timeout });
      this.socket.send(JSON.stringify({ id, method, params }));
    });
  }

  async evaluate(expression) {
    const result = await this.send('Runtime.evaluate', { expression, returnByValue: true });
    return result.result?.value;
  }

  async waitForCanvas() {
    for (let attempt = 0; attempt < 80; attempt += 1) {
      const ready = await this.evaluate("Boolean(document.querySelector('canvas')) && document.readyState === 'complete'");
      if (ready) return;
      await delay(250);
    }
    throw new Error(`${this.label}: game canvas did not load`);
  }

  async screenshot(name) {
    const result = await this.send('Page.captureScreenshot', { format: 'png', fromSurface: true });
    fs.writeFileSync(path.join(outputDirectory, `${this.label}-${name}.png`), Buffer.from(result.data, 'base64'));
  }

  async key(key, code, windowsVirtualKeyCode, holdMilliseconds = 0) {
    await this.send('Input.dispatchKeyEvent', {
      type: 'keyDown', key, code, windowsVirtualKeyCode, nativeVirtualKeyCode: windowsVirtualKeyCode,
    });
    if (holdMilliseconds > 0) await delay(holdMilliseconds);
    await this.send('Input.dispatchKeyEvent', {
      type: 'keyUp', key, code, windowsVirtualKeyCode, nativeVirtualKeyCode: windowsVirtualKeyCode,
    });
  }

  async typeText(text) {
    for (const character of text) {
      const upper = character.toUpperCase();
      const keyCode = upper.charCodeAt(0);
		await this.send('Input.dispatchKeyEvent', {
		type: 'keyDown', key: character, code: `Key${upper}`, text: character,
			unmodifiedText: character, windowsVirtualKeyCode: keyCode, nativeVirtualKeyCode: keyCode,
		});
		await this.send('Input.dispatchKeyEvent', {
			type: 'keyUp', key: character, code: `Key${upper}`,
			windowsVirtualKeyCode: keyCode, nativeVirtualKeyCode: keyCode,
		});
      await delay(35);
    }
  }

  async mouse(x, y, button = 'none') {
    await this.send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y, button: 'none' });
    if (button === 'none') return;
    await this.send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button, clickCount: 1 });
    await delay(55);
    await this.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button, clickCount: 1 });
  }

  close() {
    if (this.socket?.readyState === WebSocket.OPEN) this.socket.close();
  }
}

const players = [new CdpPage(9222, 'p1'), new CdpPage(9223, 'p2')];
let failure;
try {
  await Promise.all(players.map((player) => player.connect()));
  await Promise.all(players.map((player) => player.waitForCanvas()));
  await delay(3500);
  await Promise.all(players.map((player) => player.screenshot('01-lobby')));

  await players[0].typeText('Alpha');
  await players[0].key('Enter', 'Enter', 13);
  await delay(600);
  await players[1].typeText('Bravo');
  await players[1].key('Enter', 'Enter', 13);
  await delay(1800);
  await Promise.all(players.map((player) => player.screenshot('02-joined')));

  // Godot draws native Controls inside the canvas; direct canvas coordinates
  // are more deterministic than browser focus traversal in headless mode.
  await players[0].mouse(455, 429, 'left');
  await delay(450);
  await players[1].mouse(455, 429, 'left');
  await delay(1200);
  await Promise.all(players.map((player) => player.screenshot('03-ready')));

  // P1 is the host and owns START GAME.
  await players[0].mouse(662, 429, 'left');
  await delay(4700);

  // Exercise keyboard, mouse aim, attack, pickup, throw and both jump bindings.
  await players[0].key('d', 'KeyD', 68, 700);
  await players[1].key('a', 'KeyA', 65, 700);
  await players[0].key('w', 'KeyW', 87, 180);
  await delay(250);
  await players[1].key(' ', 'Space', 32, 180);
  await players[0].mouse(1030, 350);
  await players[0].mouse(1030, 350, 'left');
  await players[0].key('e', 'KeyE', 69);
  await players[0].mouse(980, 310, 'right');
  await players[0].key('F3', 'F3', 114);
  await delay(1800);
  await players[0].key('F10', 'F10', 121);
  await delay(800);
  await Promise.all(players.map((player) => player.screenshot('04-playing')));

  // A reload produces a real disconnect and reconnect attempt. Locked matches
  // may reject the new join, which is the expected policy during active play.
  const canvasBeforeReconnect = new Map();
  for (const player of players) {
	canvasBeforeReconnect.set(player.label, await player.evaluate("(() => { const c = document.querySelector('canvas'); return c ? { width: c.width, height: c.height } : null; })()"));
  }
  await players[1].send('Page.reload', { ignoreCache: true });
  await delay(16000);
  await players[1].screenshot('05-reconnect');

  // A real mobile user agent must stop before NetworkClient is created. Touch
  // points alone are deliberately not used so touchscreen notebooks still run.
  const mobileWebSocketsBefore = players[1].webSockets.length;
  await players[1].send('Emulation.setUserAgentOverride', {
    userAgent: 'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36',
    platform: 'Android',
    userAgentMetadata: {
      brands: [{ brand: 'Chromium', version: '124' }],
      fullVersionList: [{ brand: 'Chromium', version: '124.0.0.0' }],
      platform: 'Android',
      platformVersion: '14.0.0',
      architecture: '',
      model: 'Pixel 8',
      mobile: true,
      bitness: '',
    },
  });
  await players[1].send('Page.navigate', { url: 'http://127.0.0.1:8080' });
  await delay(5000);
  await players[1].screenshot('06-mobile-gate');
  const mobileGate = {
    userAgent: await players[1].evaluate('navigator.userAgent'),
    webSocketsCreated: players[1].webSockets.length - mobileWebSocketsBefore,
  };

  const summaries = [];
  for (const player of players) {
	const canvas = canvasBeforeReconnect.get(player.label);
    summaries.push({
      label: player.label,
      canvas,
      webSockets: player.webSockets,
      webSocketFramesReceived: player.webSocketFramesReceived,
      webSocketFramesSent: player.webSocketFramesSent,
      exceptions: player.exceptions,
      consoleErrors: player.consoleErrors.filter((message) => !message.includes('favicon')),
      mobileGate: player.label === 'p2' ? mobileGate : null,
    });
  }
  fs.writeFileSync(path.join(outputDirectory, 'summary.json'), JSON.stringify(summaries, null, 2));
  const valid = summaries.every((summary) =>
	summary.canvas?.width === 1280
	&& summary.canvas?.height === 720
    && summary.webSockets.some((url) => url.endsWith(':8080/ws'))
    && summary.webSocketFramesReceived > 10
    && summary.webSocketFramesSent > 5
    && summary.exceptions.length === 0
    && summary.consoleErrors.length === 0
    && (summary.label !== 'p2' || summary.mobileGate.webSocketsCreated === 0)
  );
  if (!valid) throw new Error(`browser verification failed: ${JSON.stringify(summaries)}`);
  console.log(`BROWSER_MULTIPLAYER_PASS ${JSON.stringify(summaries)}`);
} catch (error) {
  failure = error;
  console.error(`BROWSER_MULTIPLAYER_FAIL ${error.stack ?? error}`);
} finally {
  players.forEach((player) => player.close());
}

if (failure) process.exitCode = 1;
