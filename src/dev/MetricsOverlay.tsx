// Fork only, never for upstream: the window size and safe-area insets on
// screen, for measuring the iPhone Duo's displays (EXPO_PUBLIC_SHOW_METRICS=1
// at build time).
import React from 'react';
import { Keyboard, StyleSheet, Text, useWindowDimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useHingeValue, useTent } from '../lib/device-hinge';

export default function MetricsOverlay() {
  const { width, height } = useWindowDimensions();
  const i = useSafeAreaInsets();
  const h = useHingeValue((x) => (x ? `${x.status}/${Math.round(x.angle)}°` : null));
  const tent = useTent();
  // The keyboard's frame, for the runs that measure it on the simulator.
  const [kb, setKb] = React.useState('');
  React.useEffect(() => {
    const subs = [
      Keyboard.addListener('keyboardDidChangeFrame', (e) => {
        const c = e.endCoordinates;
        setKb(` kb x${Math.round(c.screenX)} y${Math.round(c.screenY)} ${Math.round(c.width)}x${Math.round(c.height)}`);
      }),
      Keyboard.addListener('keyboardDidHide', () => setKb(' kb hidden')),
    ];
    return () => subs.forEach((s) => s.remove());
  }, []);
  if (process.env.EXPO_PUBLIC_SHOW_METRICS !== '1') return null;
  return (
    <Text pointerEvents="none" style={styles.text}>
      {`${Math.round(width)}x${Math.round(height)} t${i.top} r${i.right} b${i.bottom} l${i.left}`}
      {h ? ` hinge ${h}${tent ? ' TENT' : ''}` : ' no hinge'}
      {kb}
    </Text>
  );
}

const styles = StyleSheet.create({
  text: {
    position: 'absolute', top: '30%', alignSelf: 'center', zIndex: 9999,
    backgroundColor: '#ffeb3bdd', color: '#000', fontSize: 14, fontWeight: '700', padding: 4,
  },
});
