# Data and API Contract

Используй существующие модели проекта. Если нужных полей нет — добавь миграции/DTO/API аккуратно и обратно-совместимо.

## Enums

```ts
export type RequestType =
  | 'city_fixed'
  | 'city_auction'
  | 'intercity'
  | 'delivery_city'
  | 'delivery_intercity'
  | 'delivery_rf';

export type PaymentMethod = 'cash' | 'card_transfer' | 'bonuses';
export type DeliveryPaymentMethod = 'cash' | 'card_transfer';
export type VehicleClass = 'economy' | 'optimal' | 'comfort' | 'business';
export type PriceSource = 'system' | 'driver_offer' | 'none';
export type LocationSource = 'geocoded' | 'map_pin' | 'manual';
```

## Location

```ts
export interface LocationValue {
  addressLabel?: string | null;
  formattedAddress?: string | null;
  displayName?: string | null;
  manualAddress?: string | null;
  lat?: number | null;
  lng?: number | null;
  source: LocationSource;
  hasUnconfirmedLocation?: boolean;
}
```

## Ride / Delivery Request

```ts
export interface InterCityRequest {
  id: string;
  requestType: RequestType;
  status: string;
  fromLocation: LocationValue;
  toLocation: LocationValue;
  paymentMethod: PaymentMethod | DeliveryPaymentMethod;
  vehicleClass?: VehicleClass | null;
  price?: number | null;
  priceSource: PriceSource;
  passengerId?: string | null;
  driverId?: string | null;
  selectedDriverId?: string | null;
  selectedOfferId?: string | null;
  comment?: string | null;
  cargo?: CargoDetails | null;
  createdAt: string;
  updatedAt: string;
}
```

## Driver Offer

```ts
export interface DriverOffer {
  id: string;
  requestId: string;
  driverId: string;
  offeredPrice: number;
  comment?: string | null;
  etaMinutes?: number | null;
  status: 'pending' | 'accepted' | 'rejected' | 'cancelled' | 'expired';
  createdAt: string;
  updatedAt: string;
}
```

## Cargo

```ts
export interface CargoDetails {
  title: string;
  description?: string | null;
  weightKg?: number | null;
  dimensions?: string | null;
  photoUrls?: string[];
  receiverName?: string | null;
  receiverPhone?: string | null;
  pickupAt?: string | null;
}
```

## Driver Balance Transaction

```ts
export interface DriverBalanceTransaction {
  id: string;
  driverId: string;
  amount: number;
  type: 'debit_intercity_accepted_request' | 'topup' | 'payout' | 'refund';
  status: 'pending' | 'completed' | 'failed' | 'reversed';
  requestId?: string | null;
  idempotencyKey: string;
  createdAt: string;
}
```

## Critical endpoints / actions

Названия адаптировать под существующий backend.

- `POST /requests/city-fixed`
- `POST /requests/city-auction`
- `POST /requests/intercity`
- `POST /requests/delivery`
- `POST /requests/:id/offers`
- `POST /requests/:id/offers/:offerId/accept`
- `POST /requests/:id/accept`
- `POST /drivers/:driverId/balance/debit-intercity-accept`
- `GET /drivers/:driverId/balance/transactions`
- `GET /geocode/search`
- `GET /geocode/reverse`

## Idempotency

Для списания комиссии использовать ключ:

```ts
const idempotencyKey = `driver:${driverId}:request:${requestId}:debit_intercity_accept`;
```

Повторный вызов с тем же ключом не должен создавать вторую транзакцию.
