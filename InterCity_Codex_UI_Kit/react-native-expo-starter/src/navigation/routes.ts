export const Routes = {
  Splash: 'Splash',
  Onboarding: 'Onboarding',
  RoleSelection: 'RoleSelection',
  PhoneLogin: 'PhoneLogin',
  SmsCode: 'SmsCode',
  PassengerHome: 'PassengerHome',
  CityModeSelection: 'CityModeSelection',
  CityFixedRoute: 'CityFixedRoute',
  CityFixedVehicleClass: 'CityFixedVehicleClass',
  CityFixedPayment: 'CityFixedPayment',
  CityFixedConfirm: 'CityFixedConfirm',
  CityAuctionCreate: 'CityAuctionCreate',
  CityAuctionOffers: 'CityAuctionOffers',
  IntercityCreate: 'IntercityCreate',
  DeliveryCreate: 'DeliveryCreate',
  DriverHome: 'DriverHome',
  DriverAvailableOrders: 'DriverAvailableOrders',
  DriverWallet: 'DriverWallet',
  Settings: 'Settings',
} as const;

export type RouteName = keyof typeof Routes;
