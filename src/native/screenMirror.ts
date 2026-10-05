import NativeScreenMirror, {
  type MirrorStatus,
} from '../../specs/NativeScreenMirror';

export type { MirrorStatus };

export type FillMode = 'fit' | 'fill';

export type MirrorSettings = {
  maxFps: number;
  jpegQuality: number;
  maxDimension: number;
  fillMode: FillMode;
};

/** O módulo nativo só existe no app iOS (não no Jest nem em outras plataformas). */
export const isMirrorAvailable = NativeScreenMirror != null;

export function getStatus(): Promise<MirrorStatus | null> {
  return NativeScreenMirror ? NativeScreenMirror.getStatus() : Promise.resolve(null);
}

export function startMirroring(): void {
  NativeScreenMirror?.showBroadcastPicker();
}

export function stopMirroring(): void {
  NativeScreenMirror?.stopBroadcast();
}

export function setDemoMode(enabled: boolean): void {
  NativeScreenMirror?.setDemoMode(enabled);
}

export function applySettings(settings: MirrorSettings): void {
  NativeScreenMirror?.setSettings(
    settings.maxFps,
    settings.jpegQuality,
    settings.maxDimension,
    settings.fillMode,
  );
}

export function settingsFromStatus(status: MirrorStatus): MirrorSettings {
  return {
    maxFps: status.maxFps,
    jpegQuality: status.jpegQuality,
    maxDimension: status.maxDimension,
    fillMode: status.fillMode === 'fill' ? 'fill' : 'fit',
  };
}
