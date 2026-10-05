import { closestFps, presetForDimension } from '../src/native/presets';

test('escolhe o preset de qualidade mais próximo', () => {
  expect(presetForDimension(960).id).toBe('economy');
  expect(presetForDimension(1300).id).toBe('balanced');
  expect(presetForDimension(2000).id).toBe('max');
});

test('escolhe a opção de FPS mais próxima', () => {
  expect(closestFps(5)).toBe(15);
  expect(closestFps(29)).toBe(30);
  expect(closestFps(60)).toBe(60);
});
