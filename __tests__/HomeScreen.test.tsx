/**
 * @format
 */

import React from 'react';
import { Platform, Text } from 'react-native';
import ReactTestRenderer from 'react-test-renderer';

import type { MirrorStatus } from '../specs/NativeScreenMirror';

const baseStatus: MirrorStatus = {
  carPlayConnected: true,
  broadcasting: false,
  demoMode: false,
  fps: 0,
  frameWidth: 0,
  frameHeight: 0,
  framesReceived: 0,
  lastFrameAgeMs: -1,
  maxFps: 30,
  jpegQuality: 0.6,
  maxDimension: 1280,
  fillMode: 'fit',
  error: '',
};

const mockModule = {
  getStatus: jest.fn(),
  showBroadcastPicker: jest.fn(),
  stopBroadcast: jest.fn(),
  setSettings: jest.fn(),
  setDemoMode: jest.fn(),
};

jest.mock('../specs/NativeScreenMirror', () => ({
  __esModule: true,
  default: mockModule,
}));

// Importado depois do mock para que o módulo nativo simulado seja usado.
const { HomeScreen } = require('../src/screens/HomeScreen');

let mounted: ReactTestRenderer.ReactTestRenderer | undefined;

async function render(status: MirrorStatus) {
  mockModule.getStatus.mockResolvedValue(status);
  await ReactTestRenderer.act(async () => {
    mounted = ReactTestRenderer.create(<HomeScreen />);
  });
  return mounted!;
}

function textContent(renderer: ReactTestRenderer.ReactTestRenderer) {
  return renderer.root
    .findAllByType(Text)
    .map(node => [node.props.children].flat().join(''));
}

function pressText(
  renderer: ReactTestRenderer.ReactTestRenderer,
  label: string,
) {
  const text = renderer.root
    .findAllByType(Text)
    .find(node => node.props.children === label);
  let node = text?.parent ?? null;
  while (node && typeof node.props.onPress !== 'function') {
    node = node.parent;
  }
  if (!node) {
    throw new Error(`Nenhum botão com o texto "${label}"`);
  }
  node.props.onPress();
}

beforeEach(() => {
  jest.clearAllMocks();
});

afterEach(async () => {
  // Desmonta para encerrar o polling de status (setInterval).
  await ReactTestRenderer.act(async () => {
    mounted?.unmount();
  });
  mounted = undefined;
});

test('inicia o espelhamento abrindo o seletor de transmissão', async () => {
  const renderer = await render(baseStatus);

  expect(textContent(renderer)).toEqual(
    expect.arrayContaining(['Conectado', 'Parada', 'Iniciar espelhamento']),
  );

  await ReactTestRenderer.act(async () => {
    pressText(renderer, 'Iniciar espelhamento');
  });
  expect(mockModule.showBroadcastPicker).toHaveBeenCalledTimes(1);
  expect(mockModule.stopBroadcast).not.toHaveBeenCalled();
});

test('para o espelhamento quando a transmissão está ativa', async () => {
  const renderer = await render({
    ...baseStatus,
    broadcasting: true,
    fps: 30,
    frameWidth: 590,
    frameHeight: 1280,
    framesReceived: 120,
  });

  expect(textContent(renderer)).toEqual(
    expect.arrayContaining(['Ativa', '590×1280', 'Parar espelhamento']),
  );

  await ReactTestRenderer.act(async () => {
    pressText(renderer, 'Parar espelhamento');
  });
  expect(mockModule.stopBroadcast).toHaveBeenCalledTimes(1);
});

test('envia as configurações escolhidas para o módulo nativo', async () => {
  const renderer = await render(baseStatus);

  await ReactTestRenderer.act(async () => {
    pressText(renderer, 'Máxima');
  });
  expect(mockModule.setSettings).toHaveBeenLastCalledWith(30, 0.8, 1920, 'fit');

  await ReactTestRenderer.act(async () => {
    pressText(renderer, 'Preencher');
  });
  expect(mockModule.setSettings).toHaveBeenLastCalledWith(
    30,
    0.8,
    1920,
    'fill',
  );
});

test('mostra o erro de configuração vindo do app nativo', async () => {
  const renderer = await render({
    ...baseStatus,
    error: 'Não foi possível usar a porta 47210.',
  });
  expect(textContent(renderer)).toContain(
    'Não foi possível usar a porta 47210.',
  );
});

test('no Android mostra Android Auto e esconde as opções exclusivas do iOS', async () => {
  const originalOS = Platform.OS;
  Platform.OS = 'android';
  try {
    const renderer = await render({
      ...baseStatus,
      broadcasting: true,
      frameWidth: 1920,
      frameHeight: 720,
    });
    const texts = textContent(renderer);
    expect(texts).toEqual(
      expect.arrayContaining([
        'Car Mirror',
        'Android Auto',
        'Resolução no carro',
        '1920×720',
      ]),
    );
    expect(texts).not.toContain('Configurações');
    expect(texts).not.toContain('FPS');

    await ReactTestRenderer.act(async () => {
      pressText(renderer, 'Parar espelhamento');
    });
    expect(mockModule.stopBroadcast).toHaveBeenCalledTimes(1);
  } finally {
    Platform.OS = originalOS;
  }
});
