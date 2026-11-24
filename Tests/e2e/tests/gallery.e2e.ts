import { appendFileSync, copyFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { test } from '@e2e-dev/mobile';
import type { Screen } from 'e2e';
import { expect } from 'e2e';
import { ipad, launch, phone } from './launch.ts';

type State = {
  device: 'ipad' | 'phone';
  xl?: boolean;
  group: string;
  frame: string;
  caption: string;
  args: string[];
  ready: string;
  steps?: (screen: Screen) => Promise<void>;
};

const states: State[] = [
  { device: 'ipad', group: 'Connect Screen', frame: 'connect-looking', caption: 'Empty / searching for Macs (SillConnectCase=looking)', args: ['-SillConnectCase', 'looking'], ready: 'Add a Mac' },
  { device: 'ipad', group: 'Connect Screen', frame: 'connect-methods', caption: 'Overloaded discovery: Wired, Wi-Fi, Direct, long Mac names', args: ['-SillConnectCase', 'methods'], ready: 'Add a Mac' },
  { device: 'ipad', group: 'Connect Screen', frame: 'connect-denied', caption: 'Permission denied (Local Network access denied)', args: ['-SillConnectCase', 'denied'], ready: 'Add a Mac' },
  { device: 'ipad', group: 'Connect Screen', frame: 'connect-error-update', caption: 'Error: Mac refused older app version', args: ['-SillConnectCase', 'update'], ready: 'Add a Mac' },
  { device: 'ipad', group: 'Connect Screen', frame: 'connect-error-remotefail', caption: 'Error: Remote connection failed', args: ['-SillConnectCase', 'remotefail'], ready: 'Add a Mac' },
  { device: 'ipad', group: 'iPad Floating Chrome', frame: 'pad-chrome-bottom', caption: 'Typical: the capsule docked at the bottom', args: [], ready: 'Apps' },
  {
    device: 'ipad', group: 'iPad Floating Chrome', frame: 'pad-chrome-trailing-aa', caption: 'Vertical trailing rail with the Aa detents open', args: [], ready: 'Apps',
    steps: async (screen) => {
      const dock = await screen.getByText('Minimize controls').boundingBox();
      await screen.swipe({ from: { x: dock.x + dock.width / 2, y: dock.y + dock.height / 2 }, to: { x: 820, y: 600 }, duration: 500 });
      await screen.getByText('Text size').tap();
      await expect(screen.getByText('Off')).toBeVisible();
    },
  },
  {
    device: 'ipad', group: 'iPad Floating Chrome', frame: 'pad-chrome-orb', caption: 'Minimized 48x48 corner orb', args: [], ready: 'Minimize controls',
    steps: async (screen) => {
      await screen.getByText('Minimize controls').tap();
      await expect(screen.getByText('Apps')).toBeHidden();
    },
  },
  { device: 'ipad', group: 'iPad Floating Chrome', frame: 'pad-chrome-desktop-aa-disabled', caption: 'Desktop streaming: Aa dimmed', args: ['-SillActive', 'desktop'], ready: 'Text size' },
  { device: 'ipad', group: 'iPad Floating Chrome', frame: 'pad-chrome-empty-none', caption: 'Empty: nothing streaming (SillActive=none)', args: ['-SillActive', 'none'], ready: 'Apps' },
  { device: 'ipad', group: 'iPad Floating Chrome', frame: 'pad-fullscreen-hint', caption: 'Full screen: controls hidden, the swipe-in hint held', args: ['-SillFullScreen', '1', '-SillFullScreenHint', 'hold'], ready: 'Controls hidden' },
  { device: 'ipad', group: 'Unified Switcher', frame: 'switcher-typical', caption: 'Typical: Desktop card, open windows, installed apps', args: ['-SillDrawer', '1'], ready: 'Windows' },
  { device: 'ipad', group: 'Control Center', frame: 'controls-typical', caption: 'Typical: tiles, Streaming, This iPad', args: ['-SillSettings', '1'], ready: 'Streaming' },
  { device: 'ipad', xl: true, group: 'Accessibility (Dynamic Type XXXL)', frame: 'connect-methods-xl', caption: 'Connect screen at accessibility-extra-extra-extra-large', args: ['-SillConnectCase', 'methods'], ready: 'Add a Mac' },
  { device: 'ipad', xl: true, group: 'Accessibility (Dynamic Type XXXL)', frame: 'controls-typical-xl', caption: 'Control Center at accessibility-extra-extra-extra-large', args: ['-SillSettings', '1'], ready: 'Done' },
  { device: 'phone', group: 'iPhone Workspace', frame: 'phone-pencilkit-bottom', caption: 'Typical: the compact capsule at the bottom', args: [], ready: 'Minimize controls' },
  {
    device: 'phone', group: 'iPhone Workspace', frame: 'phone-pencilkit-orb', caption: 'Minimized 48x48 corner orb', args: [], ready: 'Minimize controls',
    steps: async (screen) => {
      await screen.getByText('Minimize controls').tap();
      await expect(screen.getByText('Apps')).toBeHidden();
    },
  },
  {
    device: 'phone', group: 'iPhone Workspace', frame: 'phone-control-deck', caption: 'Control Deck: trackpad and command bar', args: [], ready: 'Trackpad',
    steps: async (screen) => {
      await screen.getByText('Trackpad').tap();
      await expect(screen.getByText('Stow trackpad')).toBeVisible();
    },
  },
  { device: 'phone', group: 'iPhone Workspace', frame: 'phone-switcher', caption: 'Unified Switcher on a compact width', args: ['-SillDrawer', '1'], ready: 'Windows' },
  { device: 'phone', group: 'Control Center', frame: 'phone-controls-auto', caption: 'Quality: Auto from a Mac that offers it', args: ['-SillSettings', '1', '-SillSettingsCase', 'auto'], ready: 'Streaming' },
];

const out = process.env.SILL_GALLERY_OUT ?? join(process.cwd(), '.e2e', 'states');

for (const s of states) {
  const tag = `gallery-${s.device}${s.xl ? '-xl' : ''}`;
  test(`gallery: ${s.frame}`, { tags: [tag] }, async ({ device, screen, app }) => {
    await launch(device, [...(s.device === 'ipad' ? ipad : phone), ...s.args]);
    await expect(screen.getByText(s.ready).first()).toBeVisible({ timeout: 10_000 });
    if (s.steps) await s.steps(screen);
    const shot = await app.screenshot(s.frame);
    mkdirSync(join(out, 'frames'), { recursive: true });
    copyFileSync(shot, join(out, 'frames', `${s.frame}.png`));
    appendFileSync(join(out, 'manifest.tsv'), `${s.group}\t${s.frame}\t${s.caption}\n`);
  });
}
