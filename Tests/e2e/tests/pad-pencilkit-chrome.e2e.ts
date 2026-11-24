import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { ipad, launch } from './launch.ts';

test('the iPad dock: text size, a drag to the trailing edge, the corner orb, the trackpad', { tags: ['ipad'] }, async ({ device, screen, app }) => {
  await launch(device, ipad);
  await expect(screen.getByText('Apps')).toBeVisible();
  await expect(screen.getByText('Minimize controls')).toBeVisible();
  await app.screenshot('01-pad-bottom-docked');

  await screen.getByText('Text size').tap();
  await expect(screen.getByText('Off')).toBeVisible();
  await screen.getByText('1 times').tap();
  await screen.getByText('Text size').tap();

  const dock = await screen.getByText('Minimize controls').boundingBox();
  await screen.swipe({ from: { x: dock.x + dock.width / 2, y: dock.y + dock.height / 2 }, to: { x: 820, y: 600 }, duration: 500 });
  await expect(screen.getByText('Apps')).toBeVisible();
  await screen.getByText('Text size').tap();
  await expect(screen.getByText('Off')).toBeVisible();
  await app.screenshot('02-pad-trailing-aa-open');
  await screen.getByText('Text size').tap();

  await screen.getByText('Minimize controls').tap();
  await expect(screen.getByText('Apps')).toBeHidden();
  await app.screenshot('03-pad-corner-orb');
  await screen.getByText('Controls').tap();
  await expect(screen.getByText('Apps')).toBeVisible();

  await screen.getByText('Trackpad').tap();
  await expect(screen.getByText('Move the trackpad').first()).toBeVisible();
  await app.screenshot('05-pad-floating-trackpad');
  await screen.getByText('Close the trackpad').first().tap();
  await expect(screen.getByText('Move the trackpad').first()).toBeHidden();
});
