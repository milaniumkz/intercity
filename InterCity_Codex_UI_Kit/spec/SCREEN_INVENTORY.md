# Screen Inventory

## Визуальные борды

1. `assets/design-boards/01_start_auth_light_dark.png`  
   Splash, onboarding, выбор роли, вход, SMS.

2. `assets/design-boards/02_passenger_home_city_start.png`  
   Главная пассажира, выбор режима город, поиск адреса, выбор точки на карте, начало fixed-заказа.

3. `assets/design-boards/03_city_fixed_fare_flow.png`  
   Город fixed fare: маршрут, цена, класс, оплата, подтверждение, поиск водителя.

4. `assets/design-boards/04_city_auction_flow.png`  
   Город аукцион: создание, ручной адрес, ожидание предложений, список предложений, подтверждение выбора.

5. `assets/design-boards/05_intercity_passenger_flow.png`  
   Межгород пассажира: создание заявки, доп. опции, ручной адрес, ожидание, детали поездки.

6. `assets/design-boards/06_passenger_active_history_bonus_profile.png`  
   Активная поездка, межгород в пути, мои поездки, бонусы, профиль.

7. `assets/design-boards/07_driver_onboarding_home_orders.png`  
   Регистрация водителя, авто, документы, главный экран водителя, список заказов.

8. `assets/design-boards/08_driver_city_order_flow.png`  
   Водитель: fixed-заказ, auction-заказ, предложение цены, пассажир выбрал, активная поездка.

9. `assets/design-boards/09_driver_intercity_wallet_flow.png`  
   Водитель: межгород, детали заявки, подтверждение списания, недостаточно средств, кошелёк.

10. `assets/design-boards/10_common_utility_states_settings.png`  
   Поиск адреса, адрес не найден, нет интернета, поддержка, настройки и тема.

## Полный список экранов для реализации

### Auth / Start

- SplashScreen
- OnboardingCityScreen
- OnboardingIntercityScreen
- OnboardingDeliveryScreen
- RoleSelectionScreen
- PhoneLoginScreen
- SmsCodeScreen
- PassengerRegistrationScreen
- DriverRegistrationPersonalScreen
- DriverVehicleInfoScreen
- DriverDocumentsScreen
- DriverVerificationPendingScreen

### Passenger

- PassengerHomeScreen
- CityModeSelectionScreen
- CityFixedRouteScreen
- CityFixedVehicleClassScreen
- CityFixedPaymentScreen
- CityFixedConfirmScreen
- CityFixedSearchingDriverScreen
- CityAuctionCreateScreen
- CityAuctionManualAddressScreen
- CityAuctionWaitingOffersScreen
- CityAuctionOffersListScreen
- CityAuctionConfirmDriverScreen
- IntercityCreateScreen
- IntercityOptionsScreen
- IntercityManualAddressScreen
- IntercityWaitingOffersScreen
- IntercityTripDetailsScreen
- DeliveryTypeSelectionScreen
- DeliveryCreateScreen
- DeliveryCargoDetailsScreen
- DeliveryManualAddressScreen
- DeliveryWaitingExecutorScreen
- DeliveryDetailsScreen
- PassengerActiveCityTripScreen
- PassengerActiveIntercityTripScreen
- PassengerTripsListScreen
- PassengerTripDetailsScreen
- PassengerBonusesScreen
- PassengerProfileScreen

### Driver

- DriverHomeScreen
- DriverOnlineOfflineScreen
- DriverAvailableOrdersScreen
- DriverCityFixedOrderDetailsScreen
- DriverCityAuctionOrderDetailsScreen
- DriverSendOfferScreen
- DriverOfferSentScreen
- DriverPassengerSelectedScreen
- DriverActiveTripScreen
- DriverCompleteTripScreen
- DriverIntercityOrdersScreen
- DriverIntercityOrderDetailsScreen
- DriverIntercityDebitConfirmScreen
- DriverInsufficientBalanceScreen
- DriverDeliveryOrdersScreen
- DriverDeliveryOrderDetailsScreen
- DriverActiveDeliveryScreen
- DriverOrdersHistoryScreen
- DriverWalletScreen
- DriverWalletHistoryScreen
- DriverTopUpBalanceScreen
- DriverProfileScreen

### Common

- AddressSearchScreen
- AddressNotFoundScreen
- MapPointPickerScreen
- ManualAddressScreen
- PaymentMethodSheet
- NotificationsScreen
- SettingsScreen
- ThemeSelectionScreen
- SupportScreen
- SupportTicketScreen
- NoInternetScreen
- LoadingState
- EmptyState
- ErrorState
- LocationDeniedState
