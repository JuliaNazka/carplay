import { useEffect, useState } from 'react';
import {
  Platform,
  Pressable,
  ScrollView,
  StyleSheet,
  Switch,
  Text,
  View,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import { SegmentedControl } from '../components/SegmentedControl';
import { StatusPill } from '../components/StatusPill';
import { colors, radius } from '../components/theme';
import { useMirrorStatus } from '../hooks/useMirrorStatus';
import {
  FPS_OPTIONS,
  QUALITY_PRESETS,
  closestFps,
  presetForDimension,
} from '../native/presets';
import {
  applySettings,
  isMirrorAvailable,
  setDemoMode,
  settingsFromStatus,
  startMirroring,
  stopMirroring,
  type FillMode,
  type MirrorSettings,
} from '../native/screenMirror';

const FILL_OPTIONS: { value: FillMode; label: string }[] = [
  { value: 'fit', label: 'Ajustar' },
  { value: 'fill', label: 'Preencher' },
];

const COPY = {
  ios: {
    title: 'CarPlay Mirror',
    car: 'CarPlay',
    subtitle: 'Espelhe a tela do seu iPhone direto no CarPlay.',
    steps: [
      'Conecte o iPhone ao carro e abra o CarPlay Mirror na tela do CarPlay.',
      'Toque em “Iniciar espelhamento” e depois em “Iniciar Transmissão”.',
      'Use o iPhone normalmente: a tela aparece no carro em tempo real.',
    ],
    footnote:
      'Por segurança, use o espelhamento apenas com o carro parado. Conteúdo protegido por DRM (Netflix, Prime Video etc.) aparece preto, e o toque na tela do carro não controla o iPhone.',
  },
  android: {
    title: 'Car Mirror',
    car: 'Android Auto',
    subtitle: 'Espelhe a tela do seu celular direto no Android Auto.',
    steps: [
      'Com o carro parado, conecte o celular e abra o Car Mirror na tela do Android Auto.',
      'Toque em “Iniciar espelhamento” e confirme para compartilhar a tela inteira.',
      'Use o celular normalmente: a tela aparece no carro em tempo real.',
    ],
    footnote:
      'O Android Auto só abre o Car Mirror com o carro parado; quando o carro anda, a tela do carro volta para os outros apps. Conteúdo protegido por DRM (Netflix, Prime Video etc.) aparece preto, e o toque na tela do carro não controla o celular.',
  },
};

export function HomeScreen() {
  const insets = useSafeAreaInsets();
  // No Android a imagem vai direto da GPU para o carro: FPS, qualidade, ajuste e modo
  // demonstração só existem no iOS.
  const isAndroid = Platform.OS === 'android';
  const copy = isAndroid ? COPY.android : COPY.ios;
  const { status, refresh } = useMirrorStatus();
  const [settings, setSettings] = useState<MirrorSettings | null>(null);

  // Carrega as preferências salvas no app nativo na primeira leitura de status.
  useEffect(() => {
    if (status && settings === null) {
      setSettings(settingsFromStatus(status));
    }
  }, [status, settings]);

  const updateSettings = (patch: Partial<MirrorSettings>) => {
    if (!settings) {
      return;
    }
    const next = { ...settings, ...patch };
    setSettings(next);
    applySettings(next);
    refresh();
  };

  const broadcasting = status?.broadcasting ?? false;
  const carPlayConnected = status?.carPlayConnected ?? false;
  const demoMode = status?.demoMode ?? false;
  const hasFrame = (status?.frameWidth ?? 0) > 0;

  const onPrimaryPress = () => {
    if (broadcasting) {
      stopMirroring();
    } else {
      startMirroring();
    }
    refresh();
  };

  return (
    <ScrollView
      style={styles.screen}
      contentContainerStyle={[
        styles.content,
        { paddingTop: insets.top + 16, paddingBottom: insets.bottom + 32 },
      ]}
    >
      <Text style={styles.title}>{copy.title}</Text>
      <Text style={styles.subtitle}>{copy.subtitle}</Text>

      {!isMirrorAvailable && (
        <View style={[styles.banner, styles.bannerWarning]}>
          <Text style={styles.bannerText}>
            Módulo nativo indisponível. Rode o app no celular com “npm run ios”
            ou “npm run android”.
          </Text>
        </View>
      )}

      {!!status?.error && (
        <View style={[styles.banner, styles.bannerError]}>
          <Text style={styles.bannerText}>{status.error}</Text>
        </View>
      )}

      <View style={styles.row}>
        <StatusPill
          label={copy.car}
          value={carPlayConnected ? 'Conectado' : 'Desconectado'}
          active={carPlayConnected}
        />
        <StatusPill
          label="Transmissão"
          value={broadcasting ? 'Ativa' : demoMode ? 'Demonstração' : 'Parada'}
          active={broadcasting || demoMode}
        />
      </View>

      <View style={[styles.card, styles.stats]}>
        {!isAndroid && (
          <Stat label="FPS" value={status ? String(status.fps) : '–'} />
        )}
        <Stat
          label={isAndroid ? 'Resolução no carro' : 'Resolução'}
          value={
            hasFrame && status
              ? `${status.frameWidth}×${status.frameHeight}`
              : '–'
          }
        />
        {!isAndroid && (
          <Stat
            label="Quadros"
            value={status ? String(status.framesReceived) : '–'}
          />
        )}
      </View>

      <Pressable
        accessibilityRole="button"
        disabled={!isMirrorAvailable}
        onPress={onPrimaryPress}
        style={({ pressed }) => [
          styles.primaryButton,
          broadcasting && styles.primaryButtonStop,
          pressed && styles.pressed,
          !isMirrorAvailable && styles.disabled,
        ]}
      >
        <Text style={styles.primaryButtonText}>
          {broadcasting ? 'Parar espelhamento' : 'Iniciar espelhamento'}
        </Text>
      </Pressable>

      {!isAndroid && <Text style={styles.sectionTitle}>Configurações</Text>}
      {!isAndroid && (
        <View style={styles.card}>
          <Text style={styles.label}>Quadros por segundo</Text>
          <SegmentedControl
            disabled={!settings}
            options={FPS_OPTIONS.map(fps => ({ value: fps, label: `${fps}` }))}
            value={closestFps(settings?.maxFps ?? 30)}
            onChange={maxFps => updateSettings({ maxFps })}
          />

          <Text style={styles.label}>Qualidade da imagem</Text>
          <SegmentedControl
            disabled={!settings}
            options={QUALITY_PRESETS.map(p => ({
              value: p.id,
              label: p.label,
            }))}
            value={presetForDimension(settings?.maxDimension ?? 1280).id}
            onChange={id => {
              const preset = QUALITY_PRESETS.find(p => p.id === id);
              if (preset) {
                updateSettings({
                  jpegQuality: preset.jpegQuality,
                  maxDimension: preset.maxDimension,
                });
              }
            }}
          />

          <Text style={styles.label}>Na tela do carro</Text>
          <SegmentedControl
            disabled={!settings}
            options={FILL_OPTIONS}
            value={settings?.fillMode ?? 'fit'}
            onChange={fillMode => updateSettings({ fillMode })}
          />

          <View style={styles.switchRow}>
            <View style={styles.switchText}>
              <Text style={styles.switchTitle}>Modo demonstração</Text>
              <Text style={styles.hint}>
                Mostra este app no CarPlay sem transmitir a tela. Útil para
                testar no Simulador do Xcode.
              </Text>
            </View>
            <Switch
              disabled={!isMirrorAvailable}
              value={demoMode}
              onValueChange={enabled => {
                setDemoMode(enabled);
                refresh();
              }}
            />
          </View>
        </View>
      )}

      <Text style={styles.sectionTitle}>Como usar</Text>
      <View style={styles.card}>
        {copy.steps.map((step, index) => (
          <View key={step} style={styles.step}>
            <Text style={styles.stepNumber}>{index + 1}</Text>
            <Text style={styles.stepText}>{step}</Text>
          </View>
        ))}
      </View>

      <Text style={styles.footnote}>{copy.footnote}</Text>
    </ScrollView>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <View style={styles.stat}>
      <Text style={styles.statValue}>{value}</Text>
      <Text style={styles.statLabel}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: colors.background,
  },
  content: {
    paddingHorizontal: 20,
    gap: 14,
  },
  title: {
    color: colors.text,
    fontSize: 32,
    fontWeight: '800',
  },
  subtitle: {
    color: colors.textMuted,
    fontSize: 16,
    marginTop: -8,
    marginBottom: 4,
  },
  banner: {
    borderRadius: radius.md,
    padding: 14,
  },
  bannerWarning: {
    backgroundColor: 'rgba(255, 176, 32, 0.15)',
  },
  bannerError: {
    backgroundColor: 'rgba(255, 77, 94, 0.15)',
  },
  bannerText: {
    color: colors.text,
    fontSize: 14,
    lineHeight: 20,
  },
  row: {
    flexDirection: 'row',
    gap: 12,
  },
  card: {
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    padding: 16,
    gap: 10,
  },
  stats: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  stat: {
    flex: 1,
    alignItems: 'center',
    gap: 2,
  },
  statValue: {
    color: colors.text,
    fontSize: 20,
    fontWeight: '700',
    fontVariant: ['tabular-nums'],
  },
  statLabel: {
    color: colors.textMuted,
    fontSize: 12,
    fontWeight: '600',
  },
  primaryButton: {
    backgroundColor: colors.accent,
    borderRadius: radius.lg,
    paddingVertical: 18,
    alignItems: 'center',
  },
  primaryButtonStop: {
    backgroundColor: colors.danger,
  },
  primaryButtonText: {
    color: '#FFFFFF',
    fontSize: 18,
    fontWeight: '700',
  },
  pressed: {
    opacity: 0.8,
  },
  disabled: {
    opacity: 0.4,
  },
  sectionTitle: {
    color: colors.text,
    fontSize: 20,
    fontWeight: '700',
    marginTop: 10,
  },
  label: {
    color: colors.textMuted,
    fontSize: 13,
    fontWeight: '600',
    marginTop: 4,
  },
  switchRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
    marginTop: 6,
  },
  switchText: {
    flex: 1,
    gap: 2,
  },
  switchTitle: {
    color: colors.text,
    fontSize: 15,
    fontWeight: '600',
  },
  hint: {
    color: colors.textMuted,
    fontSize: 13,
    lineHeight: 18,
  },
  step: {
    flexDirection: 'row',
    gap: 12,
    alignItems: 'flex-start',
  },
  stepNumber: {
    color: colors.accent,
    fontSize: 15,
    fontWeight: '800',
    width: 18,
  },
  stepText: {
    flex: 1,
    color: colors.text,
    fontSize: 15,
    lineHeight: 21,
  },
  footnote: {
    color: colors.textMuted,
    fontSize: 13,
    lineHeight: 19,
    marginTop: 6,
  },
});
