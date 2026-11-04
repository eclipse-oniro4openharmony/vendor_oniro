/*
 * Copyright (c) 2026 Eclipse Oniro for OpenHarmony contributors.
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { camera } from '@kit.CameraKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0F1A;
const TAG = 'Flashlight';

/*
 * One button that switches the torch through the camera service
 * (CameraManager.setTorchMode).  The state follows the service's
 * torchStatusChange events, so it stays right when the torch is switched
 * elsewhere or turned off because the camera was opened.
 */
@Entry
@Component
struct Index {
  @State isOn: boolean = false;
  @State supported: boolean = true;
  @State available: boolean = true;
  private manager: camera.CameraManager | undefined = undefined;

  aboutToAppear(): void {
    try {
      this.manager = camera.getCameraManager(this.getUIContext().getHostContext());
      this.supported = this.manager.isTorchSupported();
      this.isOn = this.manager.getTorchMode() === camera.TorchMode.ON;
      this.manager.on('torchStatusChange', (err: BusinessError, info: camera.TorchStatusInfo) => {
        if (err !== undefined && err !== null && err.code !== 0) {
          hilog.error(DOMAIN, TAG, 'torchStatusChange error %{public}d', err.code);
          return;
        }
        this.isOn = info.isTorchActive;
        this.available = info.isTorchAvailable;
      });
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'camera manager unavailable: %{public}d %{public}s', err.code, err.message);
      this.supported = false;
    }
  }

  aboutToDisappear(): void {
    try {
      this.manager?.off('torchStatusChange');
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'off(torchStatusChange) failed');
    }
  }

  private toggle(): void {
    if (this.manager === undefined) {
      return;
    }
    const target = !this.isOn;
    try {
      this.manager.setTorchMode(target ? camera.TorchMode.ON : camera.TorchMode.OFF);
      this.isOn = target;
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'setTorchMode(%{public}d) failed: %{public}d %{public}s', target ? 1 : 0,
        err.code, err.message);
      this.available = false;
    }
  }

  private statusText(): Resource {
    if (!this.supported) {
      return $r('app.string.status_unsupported');
    }
    if (!this.available) {
      return $r('app.string.status_busy');
    }
    return this.isOn ? $r('app.string.status_on') : $r('app.string.status_off');
  }

  build() {
    Column({ space: 40 }) {
      Button({ type: ButtonType.Circle, stateEffect: true }) {
        SymbolGlyph(this.isOn ? $r('sys.symbol.flashlight_on_fill') : $r('sys.symbol.flashlight_off_fill'))
          .fontSize(96)
          .fontColor([this.isOn ? '#1C1C1E' : '#F2F2F7'])
      }
      .width(200)
      .height(200)
      .backgroundColor(this.isOn ? '#FFD60A' : '#3A3A3C')
      .enabled(this.supported && this.available)
      .opacity(this.supported && this.available ? 1 : 0.4)
      .onClick(() => this.toggle())
      .id('torch_toggle')

      Text(this.statusText())
        .fontSize(20)
        .fontColor('#F2F2F7')
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.isOn ? '#2A2410' : '#000000')
    .animation({ duration: 200 })
  }
}
