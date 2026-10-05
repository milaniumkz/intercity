import React from 'react';
import { SafeAreaView, ScrollView, StyleSheet, View, ViewStyle } from 'react-native';
import { useICTheme } from '../theme/useICTheme';

export function ICScreen({ children, scroll = true, style }: { children: React.ReactNode; scroll?: boolean; style?: ViewStyle }) {
  const { theme } = useICTheme();
  const content = <View style={[styles.content, style]}>{children}</View>;
  return (
    <SafeAreaView style={[styles.root, { backgroundColor: theme.background.primary }]}>
      {scroll ? <ScrollView contentContainerStyle={styles.scroll}>{content}</ScrollView> : content}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1 },
  scroll: { flexGrow: 1 },
  content: { flex: 1, paddingHorizontal: 20, paddingVertical: 16 },
});
