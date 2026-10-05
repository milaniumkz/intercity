import React from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { useICTheme } from '../theme/useICTheme';

type Variant = 'primary' | 'secondary' | 'ghost';

export function ICButton({ title, onPress, disabled, loading, variant = 'primary' }: {
  title: string;
  onPress?: () => void;
  disabled?: boolean;
  loading?: boolean;
  variant?: Variant;
}) {
  const { theme } = useICTheme();
  const isPrimary = variant === 'primary';
  const opacity = disabled ? 0.45 : 1;

  return (
    <Pressable onPress={onPress} disabled={disabled || loading} style={({ pressed }) => [{ opacity: pressed ? opacity * 0.85 : opacity }]}>
      {isPrimary ? (
        <LinearGradient colors={[theme.accent.secondary, theme.accent.primary]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={styles.button}>
          {loading ? <ActivityIndicator color="#fff" /> : <Text style={styles.primaryText}>{title}</Text>}
        </LinearGradient>
      ) : (
        <Text style={[styles.secondary, { color: theme.accent.primary, borderColor: variant === 'secondary' ? theme.accent.primary : 'transparent' }]}>{title}</Text>
      )}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  button: { height: 54, borderRadius: 16, alignItems: 'center', justifyContent: 'center' },
  primaryText: { color: '#FFFFFF', fontSize: 16, fontWeight: '700' },
  secondary: { height: 52, borderRadius: 16, borderWidth: 1, textAlign: 'center', textAlignVertical: 'center', fontSize: 16, fontWeight: '700', paddingTop: 14 },
});
