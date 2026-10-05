import React from 'react';
import { StyleSheet, TextInput, TextInputProps, View } from 'react-native';
import { useICTheme } from '../theme/useICTheme';
import { ICText } from './ICText';

export function ICTextInput({ label, error, ...props }: TextInputProps & { label?: string; error?: string }) {
  const { theme } = useICTheme();
  return (
    <View style={styles.wrap}>
      {label ? <ICText variant="caption" color="secondary" style={styles.label}>{label}</ICText> : null}
      <TextInput
        placeholderTextColor={theme.text.tertiary}
        style={[styles.input, { backgroundColor: theme.background.secondary, borderColor: error ? '#E24A5A' : theme.border.light, color: theme.text.primary }]}
        {...props}
      />
      {error ? <ICText variant="caption" style={{ color: '#E24A5A', marginTop: 6 }}>{error}</ICText> : null}
    </View>
  );
}

const styles = StyleSheet.create({
  wrap: { marginBottom: 14 },
  label: { marginBottom: 8 },
  input: { height: 52, borderRadius: 14, borderWidth: 1, paddingHorizontal: 14, fontSize: 15 },
});
