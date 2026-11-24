import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { launch, phone } from './launch.ts';

test('the iPhone dock: the orb, the Control Deck, Control Center and the Mac menus', { tags: ['phone'] }, async ({ device, screen, app }) => {
  await launch(device, phone);
  for (const label of ['Apps', 'Keyboard', 'Trackpad', 'Controls', 'Minimize controls']) {
    await expect(screen.getByText(label)).toBeVisible();
  }
  await app.screenshot('01-phone-pencilkit-bottom');

  await screen.getByText('Minimize controls').tap();
  await expect(screen.getByText('Apps')).toBeHidden();
  await screen.getByText('Controls').tap();
  await expect(screen.getByText('Apps')).toBeVisible();

  await screen.getByText('Trackpad').tap();
  await expect(screen.getByText('Stow trackpad')).toBeVisible();
  await app.screenshot('03-phone-control-deck');
  await screen.getByText('Stow trackpad').tap();
  await expect(screen.getByText('Minimize controls')).toBeVisible();

  await screen.getByText('Controls').tap();
  await expect(screen.getByText('Full Screen').first()).toBeVisible();
  await app.screenshot('04-phone-control-center');
  await screen.getByText('Menus').first().tap();
  await expect(screen.getByText('File')).toBeVisible();
  await app.screenshot('05-phone-mac-menus');
  await screen.getByText('Done').tap();
  await expect(screen.getByText('Apps')).toBeVisible();
});
