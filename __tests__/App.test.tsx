/**
 * @format
 */

import React from 'react';
import { Text } from 'react-native';
import ReactTestRenderer from 'react-test-renderer';
import App from '../App';

test('mostra aviso quando o módulo nativo não está disponível', async () => {
  let renderer: ReactTestRenderer.ReactTestRenderer | undefined;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });

  const texts = renderer!.root
    .findAllByType(Text)
    .map(node => [node.props.children].flat().join(''));
  expect(texts.some(t => t.includes('Módulo nativo indisponível'))).toBe(true);
  expect(texts).toContain('Iniciar espelhamento');

  await ReactTestRenderer.act(() => {
    renderer!.unmount();
  });
});
