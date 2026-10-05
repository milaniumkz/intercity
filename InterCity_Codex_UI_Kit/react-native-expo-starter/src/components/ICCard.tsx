import React from 'react';
import { StyleSheet, View, ViewStyle } from 'react-native';
import { useICTheme } from '../theme/useICTheme';

export function ICCard({ children, style }: { children: React.ReactNode; style?: ViewStyle }) {
  const { theme, mode } = useICTheme();
  return (
    <View style={[
      styles.card,
      {
        backgroundColor: theme.background.elevated,
        borderColor: theme.border.light,
        shadowOpacity: mode === 'dark' ? 0 : 0.08,
      },
      style,
    ]}>
      {children}
    </View>
  );
}

const styles = StyleSheet.create({
  card: {
    borderRadius: 20,
    borderWidth: 1,
    padding: 16,
    shadowColor: '#2C174C',
    shadowOffset: { width: 0, height: 12 },
    shadowRadius: 24,
    elevation: 3,
  },
});
