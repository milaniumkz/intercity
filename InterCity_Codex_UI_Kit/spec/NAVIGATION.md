# Navigation Structure

## Root

```txt
RootNavigator
├── AuthStack
├── PassengerTabs
├── DriverTabs
└── CommonModals
```

## AuthStack

```txt
Splash
Onboarding
RoleSelection
PhoneLogin
SmsCode
PassengerRegistration
DriverRegistrationPersonal
DriverVehicleInfo
DriverDocuments
DriverVerificationPending
```

## PassengerTabs

```txt
PassengerTabs
├── HomeStack
│   ├── PassengerHome
│   ├── CityModeSelection
│   ├── CityFixedRoute
│   ├── CityFixedVehicleClass
│   ├── CityFixedPayment
│   ├── CityFixedConfirm
│   ├── CityFixedSearchingDriver
│   ├── CityAuctionCreate
│   ├── CityAuctionManualAddress
│   ├── CityAuctionWaitingOffers
│   ├── CityAuctionOffersList
│   ├── CityAuctionConfirmDriver
│   ├── IntercityCreate
│   ├── IntercityOptions
│   ├── IntercityWaitingOffers
│   ├── DeliveryTypeSelection
│   ├── DeliveryCreate
│   ├── DeliveryDetails
│   ├── AddressSearch
│   ├── AddressNotFound
│   ├── MapPointPicker
│   └── ManualAddress
├── TripsStack
├── BonusesStack
└── ProfileStack
```

## DriverTabs

```txt
DriverTabs
├── DriverHomeStack
│   ├── DriverHome
│   ├── DriverAvailableOrders
│   ├── DriverCityFixedOrderDetails
│   ├── DriverCityAuctionOrderDetails
│   ├── DriverSendOffer
│   ├── DriverPassengerSelected
│   ├── DriverActiveTrip
│   ├── DriverIntercityOrders
│   ├── DriverIntercityOrderDetails
│   ├── DriverIntercityDebitConfirm
│   ├── DriverInsufficientBalance
│   ├── DriverDeliveryOrders
│   └── DriverActiveDelivery
├── DriverOrdersHistoryStack
├── DriverWalletStack
└── DriverProfileStack
```

## Shared Modals / Sheets

- PaymentMethodSheet
- VehicleClassSheet
- CancelOrderSheet
- DriverOfferConfirmSheet
- ThemeSelectionSheet
