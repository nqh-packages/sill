import type { Device } from '@e2e-dev/mobile';

export const ipad = ['-SillLayout', '834x1194'];
export const phone = ['-SillLayout', '402x874', '-SillIdiom', 'phone'];

export async function launch(device: Device, launchArguments: string[]): Promise<void> {
  await device.openApp('com.uxheavy.sill', { relaunch: true, launchArguments });
}
