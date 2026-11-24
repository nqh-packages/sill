import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { ipad, launch } from './launch.ts';

test('the switcher picks the Desktop, then Control Center opens', { tags: ['ipad'] }, async ({ device, screen, app }) => {
  await launch(device, ipad);
  await screen.getByText('Apps').tap();
  await expect(screen.getByText('Done')).toBeVisible();
  await expect(screen.getByText('Windows')).toBeVisible();
  await app.screenshot('01-switcher-open');

  await screen.getByText('Desktop').first().tap();
  await expect(screen.getByText('Controls')).toBeVisible();
  await app.screenshot('02-desktop-active');

  await screen.getByText('Controls').tap();
  await expect(screen.getByText('Streaming')).toBeVisible();
  await screen.getByRole('button', { name: 'Sheet Grabber' }).tap();
  await screen.scrollUntilVisible(screen.getByText('This iPad'));
  await app.screenshot('03-control-center-root');
  await screen.scrollUntilVisible(screen.getByText('Disconnect from Mac mini'));
  await app.screenshot('04-control-center-bottom');
});

test('the Apps key opens the switcher with the search focused, and Done closes it', { tags: ['ipad'] }, async ({ device, screen, app }) => {
  await launch(device, ipad);
  await screen.getByText('Apps').tap();
  await expect(screen.getByText('Done')).toBeVisible();
  await expect(screen.getByRole('textbox', { name: 'Search windows & Mac apps' })).toBeFocused();
  await app.screenshot('01-search-focused');

  await screen.getByText('Done').tap();
  await expect(screen.getByText('Controls')).toBeVisible();
  await screen.getByText('Apps').tap();
  await expect(screen.getByText('Done')).toBeVisible();
});

test('a switcher opened without the keyboard filters by what is typed in its search', { tags: ['ipad'] }, async ({ device, screen, app }) => {
  await launch(device, [...ipad, '-SillDrawer', '1']);
  await expect(screen.getByText('Windows')).toBeVisible();
  await screen.getByRole('textbox', { name: 'Search windows & Mac apps' }).fill('Pack');
  await expect(screen.getByText('Packing list')).toBeVisible();
  await expect(screen.getByText('Team chat')).toBeHidden();
  await app.screenshot('01-filtered');

  await screen.getByText('Done').tap();
  await expect(screen.getByText('Controls')).toBeVisible();
});

test('dragging Control Center from half to full height keeps it responsive', { tags: ['ipad'] }, async ({ device, screen }) => {
  await launch(device, [...ipad, '-SillSettings', '1']);
  await expect(screen.getByText('Streaming')).toBeVisible();
  await screen.swipe({ from: { x: 417, y: 900 }, to: { x: 417, y: 250 }, duration: 400 });
  await screen.swipe({ from: { x: 417, y: 900 }, to: { x: 417, y: 250 }, duration: 400 });
  await screen.getByText('Done').tap();
  await expect(screen.getByText('Controls')).toBeVisible();
});
