import React, { createContext, useContext, useMemo, useState } from 'react';
import { ColorSchemeName, useColorScheme } from 'react-native';
import { interCityTokens, InterCityThemeMode } from './tokens';

type ThemePreference = 'system' | InterCityThemeMode;

type ICThemeContextValue = {
  preference: ThemePreference;
  mode: InterCityThemeMode;
  theme: typeof interCityTokens.light;
  setPreference: (preference: ThemePreference) => void;
};

const ICThemeContext = createContext<ICThemeContextValue | null>(null);

function resolveMode(preference: ThemePreference, system: ColorSchemeName): InterCityThemeMode {
  if (preference === 'light' || preference === 'dark') return preference;
  return system === 'dark' ? 'dark' : 'light';
}

export function ICThemeProvider({ children }: { children: React.ReactNode }) {
  const system = useColorScheme();
  const [preference, setPreference] = useState<ThemePreference>('system');
  const mode = resolveMode(preference, system);
  const theme = mode === 'dark' ? interCityTokens.dark : interCityTokens.light;

  const value = useMemo(() => ({ preference, mode, theme, setPreference }), [preference, mode, theme]);
  return <ICThemeContext.Provider value={value}>{children}</ICThemeContext.Provider>;
}

export function useICTheme() {
  const ctx = useContext(ICThemeContext);
  if (!ctx) throw new Error('useICTheme must be used inside ICThemeProvider');
  return ctx;
}
