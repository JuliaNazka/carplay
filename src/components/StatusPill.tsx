import { StyleSheet, Text, View } from 'react-native';

import { colors, radius } from './theme';

type Props = {
  label: string;
  value: string;
  active: boolean;
};

export function StatusPill({ label, value, active }: Props) {
  return (
    <View style={styles.container}>
      <View style={styles.row}>
        <View
          style={[
            styles.dot,
            { backgroundColor: active ? colors.success : colors.textMuted },
          ]}
        />
        <Text style={styles.label}>{label}</Text>
      </View>
      <Text style={styles.value}>{value}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.surface,
    borderRadius: radius.md,
    padding: 14,
    gap: 6,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  dot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  label: {
    color: colors.textMuted,
    fontSize: 13,
    fontWeight: '600',
  },
  value: {
    color: colors.text,
    fontSize: 17,
    fontWeight: '700',
  },
});
