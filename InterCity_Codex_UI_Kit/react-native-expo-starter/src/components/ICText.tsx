import React from 'react';
import { Text, TextProps } from 'react-native';
import { useICTheme } from '../theme/useICTheme';

type Variant = 'h1' | 'h2' | 'h3' | 'body' | 'small' | 'caption';

const stylesByVariant = {
  h1: { fontSize: 28, lineHeight: 34, fontWeight: '700' as const },
  h2: { fontSize: 24, lineHeight: 30, fontWeight: '700' as const },
  h3: { fontSize: 20, lineHeight: 26, fontWeight: '700' as const },
  body: { fontSize: 15, lineHeight: 22, fontWeight: '400' as const },
  small: { fontSize: 13, lineHeight: 18, fontWeight: '400' as const },
  caption: { fontSize: 12, lineHeight: 16, fontWeight: '600' as const },
};

export function ICText({ variant = 'body', color = 'primary', style, ...props }: TextProps & { variant?: Variant; color?: 'primary' | 'secondary' | 'tertiary' | 'accent' }) {
  const { theme } = useICTheme();
  const textColor = color === 'accent' ? theme.accent.primary : theme.text[color];
  return <Text {...props} style={[stylesByVariant[variant], { color: textColor }, style]} />;
}
