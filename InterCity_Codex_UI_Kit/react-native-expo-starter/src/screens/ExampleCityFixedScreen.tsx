import React, { useMemo, useState } from 'react';
import { View } from 'react-native';
import { ICButton } from '../components/ICButton';
import { ICCard } from '../components/ICCard';
import { ICScreen } from '../components/ICScreen';
import { ICText } from '../components/ICText';
import { PaymentSelector, PaymentMethod } from '../components/PaymentSelector';
import { VehicleClass, VehicleClassSelector } from '../components/VehicleClassSelector';

const basePrices: Record<VehicleClass, number> = {
  economy: 1780,
  optimal: 2280,
  comfort: 2980,
  business: 3980,
};

export function ExampleCityFixedScreen() {
  const [vehicleClass, setVehicleClass] = useState<VehicleClass>('comfort');
  const [paymentMethod, setPaymentMethod] = useState<PaymentMethod>('card_transfer');
  const price = useMemo(() => basePrices[vehicleClass], [vehicleClass]);

  return (
    <ICScreen>
      <ICText variant="h1">Ваш маршрут</ICText>
      <ICCard style={{ marginTop: 16 }}>
        <ICText variant="body" style={{ fontWeight: '700' }}>Москва</ICText>
        <ICText color="secondary">Ленинградский вокзал</ICText>
        <View style={{ height: 12 }} />
        <ICText variant="body" style={{ fontWeight: '700' }}>Шереметьево SVO</ICText>
        <ICText color="secondary">Терминал B</ICText>
      </ICCard>

      <View style={{ height: 20 }} />
      <ICText variant="h2">Выберите класс</ICText>
      <VehicleClassSelector value={vehicleClass} prices={basePrices} onChange={setVehicleClass} />

      <View style={{ height: 20 }} />
      <ICText variant="h2">Способ оплаты</ICText>
      <PaymentSelector value={paymentMethod} onChange={setPaymentMethod} />

      <View style={{ flex: 1 }} />
      <ICCard style={{ marginTop: 24, marginBottom: 12 }}>
        <ICText color="secondary">Цена поездки</ICText>
        <ICText variant="h1" color="accent">{price.toLocaleString('ru-RU')} ₽</ICText>
      </ICCard>
      <ICButton title={`Заказать за ${price.toLocaleString('ru-RU')} ₽`} />
    </ICScreen>
  );
}
