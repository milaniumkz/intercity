# Utility Functions

## formatLocationDisplay

```ts
export function formatLocationDisplay(location?: LocationValue | null): string {
  if (!location) return 'Адрес не указан';

  const manual = location.manualAddress?.trim();
  if (manual) return manual;

  const label = location.addressLabel?.trim()
    || location.formattedAddress?.trim()
    || location.displayName?.trim();
  if (label && !looksLikeCoordinates(label)) return label;

  if (location.lat != null && location.lng != null) {
    return 'Выбранная точка на карте';
  }

  return 'Адрес не указан';
}

export function looksLikeCoordinates(value: string): boolean {
  return /^-?\d+(\.\d+)?[,\s]+-?\d+(\.\d+)?$/.test(value.trim());
}
```

## getAvailablePaymentMethods

```ts
export function getAvailablePaymentMethods(requestType: RequestType): PaymentMethod[] {
  if (requestType.startsWith('delivery')) return ['cash', 'card_transfer'];
  return ['cash', 'card_transfer', 'bonuses'];
}
```

## validateRequestDraft

Правила:

- `city_fixed`: нужны координаты А/В, маршрут и системная цена.
- `city_auction`: нужны адреса А/В, координаты необязательны.
- `intercity`: нужны адреса А/В, координаты необязательны.
- `delivery_*`: нужны адреса А/В, описание груза, бонусы запрещены.
