import { Pressable, StyleSheet, Text, View } from 'react-native';

import { colors, radius } from './theme';

type Option<T extends string | number> = { value: T; label: string };

type Props<T extends string | number> = {
  options: Option<T>[];
  value: T;
  onChange: (value: T) => void;
  disabled?: boolean;
};

export function SegmentedControl<T extends string | number>({
  options,
  value,
  onChange,
  disabled,
}: Props<T>) {
  return (
    <View style={[styles.container, disabled && styles.disabled]}>
      {options.map(option => {
        const selected = option.value === value;
        return (
          <Pressable
            key={String(option.value)}
            accessibilityRole="button"
            accessibilityState={{ selected, disabled }}
            disabled={disabled}
            onPress={() => onChange(option.value)}
            style={[styles.segment, selected && styles.segmentSelected]}
          >
            <Text style={[styles.label, selected && styles.labelSelected]}>
              {option.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    backgroundColor: colors.background,
    borderRadius: radius.sm,
    padding: 3,
    gap: 3,
  },
  disabled: {
    opacity: 0.5,
  },
  segment: {
    flex: 1,
    paddingVertical: 9,
    borderRadius: radius.sm - 2,
    alignItems: 'center',
  },
  segmentSelected: {
    backgroundColor: colors.surfaceRaised,
  },
  label: {
    color: colors.textMuted,
    fontSize: 14,
    fontWeight: '600',
  },
  labelSelected: {
    color: colors.text,
  },
});
