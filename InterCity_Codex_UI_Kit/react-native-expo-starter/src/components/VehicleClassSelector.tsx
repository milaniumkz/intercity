import React from 'react';
import { Pressable, StyleSheet, View } from 'react-native';
import { useICTheme } from '../theme/useICTheme';
import { ICCard } from './ICCard';
import { ICText } from './ICText';

export type VehicleClass = 'economy' | 'optimal' | 'comfort' | 'business';

const labels: Record<VehicleClass, { title: string; desc: string }> = {
  economy: { title: 'Эконом', desc: 'Быстро и выгодно' },
  optimal: { title: 'Оптимал', desc: 'Лучший баланс' },
  comfort: { title: 'Комфорт', desc: 'Больше удобства' },
  business: { title: 'Бизнес', desc: 'Премиальная поездка' },
};

export function VehicleClassSelector({ value, prices, onChange }: {
  value: VehicleClass;
  prices: Record<VehicleClass, number>;
  onChange: (value: VehicleClass) => void;
}) {
  const { theme } = useICTheme();
  return (
    <View style={styles.list}>
      {(Object.keys(labels) as VehicleClass[]).map((cls) => {
        const selected = cls === value;
        return (
          <Pressable key={cls} onPress={() => onChange(cls)}>
            <ICCard style={{ borderColor: selected ? theme.accent.primary : theme.border.light, backgroundColor: selected ? theme.accent.soft : theme.background.elevated }}>
              <View style={styles.row}>
                <View>
                  <ICText variant="body" color={selected ? 'accent' : 'primary'} style={{ fontWeight: '700' }}>{labels[cls].title}</ICText>
                  <ICText variant="small" color="secondary">{labels[cls].desc}</ICText>
                </View>
                <ICText variant="body" color="accent" style={{ fontWeight: '700' }}>{prices[cls].toLocaleString('ru-RU')} ₽</ICText>
              </View>
            </ICCard>
          </Pressable>
        );
      })}
    </View>
  );
}

const styles = StyleSheet.create({ list: { gap: 10 }, row: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' } });
