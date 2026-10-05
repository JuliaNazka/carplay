import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export type MirrorStatus = {
  /** O app está aberto na tela do CarPlay (cena do CarPlay conectada). */
  carPlayConnected: boolean;
  /** A extensão de transmissão (ReplayKit) está conectada e enviando quadros. */
  broadcasting: boolean;
  /** Modo demonstração: espelha a própria tela do app (útil no Simulador). */
  demoMode: boolean;
  /** Quadros exibidos por segundo no último segundo. */
  fps: number;
  frameWidth: number;
  frameHeight: number;
  framesReceived: number;
  /** Milissegundos desde o último quadro recebido (-1 se nenhum). */
  lastFrameAgeMs: number;
  maxFps: number;
  jpegQuality: number;
  maxDimension: number;
  /** 'fit' (ajustar) ou 'fill' (preencher). */
  fillMode: string;
  /** Mensagem de erro de configuração (App Group, socket etc.) ou string vazia. */
  error: string;
};

export interface Spec extends TurboModule {
  getStatus(): Promise<MirrorStatus>;
  showBroadcastPicker(): void;
  stopBroadcast(): void;
  setSettings(
    maxFps: number,
    jpegQuality: number,
    maxDimension: number,
    fillMode: string,
  ): void;
  setDemoMode(enabled: boolean): void;
}

export default TurboModuleRegistry.get<Spec>('ScreenMirror');
