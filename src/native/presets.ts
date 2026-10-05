export type QualityPreset = {
  id: 'economy' | 'balanced' | 'max';
  label: string;
  jpegQuality: number;
  maxDimension: number;
};

/** Resolução (lado maior) e compressão JPEG de cada nível de qualidade. */
export const QUALITY_PRESETS: QualityPreset[] = [
  { id: 'economy', label: 'Economia', jpegQuality: 0.45, maxDimension: 960 },
  { id: 'balanced', label: 'Equilíbrio', jpegQuality: 0.6, maxDimension: 1280 },
  { id: 'max', label: 'Máxima', jpegQuality: 0.8, maxDimension: 1920 },
];

export const FPS_OPTIONS = [15, 30, 60] as const;

/** Encontra o preset mais próximo da resolução configurada no app nativo. */
export function presetForDimension(maxDimension: number): QualityPreset {
  return QUALITY_PRESETS.reduce((best, preset) =>
    Math.abs(preset.maxDimension - maxDimension) <
    Math.abs(best.maxDimension - maxDimension)
      ? preset
      : best,
  );
}

/** Encontra a opção de FPS mais próxima do valor configurado. */
export function closestFps(maxFps: number): number {
  return FPS_OPTIONS.reduce<number>(
    (best, option) =>
      Math.abs(option - maxFps) < Math.abs(best - maxFps) ? option : best,
    FPS_OPTIONS[0],
  );
}
