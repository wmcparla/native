import React from 'react';
import { Keyboard, Platform, TextInput, useWindowDimensions } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useHalfOpen } from './device-hinge';
import { TAB_RAIL_WIDTH, foldAlignedPanes, laptopFoldY, layoutFor, tabBarPositionFor } from './use-layout';

/**
 * The list's width in a tab's list-detail split (Contacts, Settings) on an
 * iPhone Duo half open like a book: the list ends at the fold, as the Mail
 * tab's does (`foldAlignedPanes`), while both panes keep their minimum
 * widths. Anywhere else, `listWidth` as it is. `room` is the width the list
 * and the detail share. Not for Files: its docked preview needs 440 pt for
 * its header, more than the Duo's fold leaves it (391).
 */
export function useFoldAlignedListWidth(listWidth: number, room: number): number {
  const halfOpen = useHalfOpen();
  const { width, height } = useWindowDimensions();
  const { top, left, right } = useSafeAreaInsets();
  if (!halfOpen || width <= height) return listWidth;
  const window = layoutFor(width, height);
  const rail = tabBarPositionFor(window, width, { top, left, right }) === 'left' ? TAB_RAIL_WIDTH : 0;
  const split = { ...window, isSplit: true, listWidth, detailWidth: room - listWidth };
  return foldAlignedPanes(split, width, left + rail).listWidth;
}

/**
 * Where the fold crosses the window of an iPhone Duo half open like a laptop
 * (`laptopFoldY`), else null. A tab's list-detail split stacks there instead:
 * the detail over the top of the row down to the fold, the list below it.
 */
export function useLaptopFoldY(): number | null {
  const halfOpen = useHalfOpen();
  const { width, height } = useWindowDimensions();
  return laptopFoldY(halfOpen, width, height);
}

/**
 * Whether the keyboard is up for a field below the fold of a stacked layout
 * (`foldY`). On an iPhone Duo half open like a laptop the keyboard covers
 * most of the half lying flat, the list's search field with it, so the list
 * then takes the whole screen until the keyboard goes. Judged when the
 * keyboard comes up, by where the focused field is: once the list has moved
 * up its field is above the fold, which must not send it back down.
 */
export function useTypingBelowFold(foldY: number | null): boolean {
  const [below, setBelow] = React.useState(false);
  React.useEffect(() => {
    if (foldY == null) {
      setBelow(false);
      return undefined;
    }
    const shown = Keyboard.addListener(Platform.OS === 'ios' ? 'keyboardWillShow' : 'keyboardDidShow', () => {
      const field = TextInput.State.currentlyFocusedInput();
      if (!field) return;
      field.measureInWindow((_x, y) => setBelow((was) => was || y >= foldY));
    });
    const hidden = Keyboard.addListener(Platform.OS === 'ios' ? 'keyboardWillHide' : 'keyboardDidHide', () => setBelow(false));
    return () => {
      shown.remove();
      hidden.remove();
    };
  }, [foldY]);
  return foldY != null && below;
}
