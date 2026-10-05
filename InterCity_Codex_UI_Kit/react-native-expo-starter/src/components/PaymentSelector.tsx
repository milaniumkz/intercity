import React from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import { useICTheme } from '../theme/useICTheme';
import { ICCard } from './ICCard';
import { ICText } from './ICText';

export type PaymentMethod = 'cash' | 'card_transfer' | 'bonuses';

const labels: Record<PaymentMethod, string> = {
  cash: 'Наличными',
  card_transfer: 'На карту',
  bonuses: 'Бонусами',
};

export function PaymentSelector({ value, onChange, allowBonuses = true }: {
  value: PaymentMethod;
  onChange: (value: PaymentMethod) => void;
  allowBonuses?: boolean;
}) {
  const { theme } = useICTheme();
  const methods: PaymentMethod[] = allowBonuses ? ['cash', 'card_transfer', 'bonuses'] : ['cash', 'card_transfer'];
  return (
    <View style={styles.list}>
      {methods.map((method) => {
        const selected = method === value;
        return (
          <Pressable key={method} onPress={() => onChange(method)}>
            <ICCard style={{ borderColor: selected ? theme.accent.primary : theme.border.light, backgroundColor: selected ? theme.accent.soft : theme.background.elevated }}>
              <ICText variant="body" color={selected ? 'accent' : 'primary'} style={{ fontWeight: '700' }}>{labels[method]}</ICText>
            </ICCard>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({ list: { gap: 10 } });
