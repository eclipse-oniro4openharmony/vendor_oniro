/* Copyright (c) 2022 Diemit <598757652@qq.com>
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
 *
 */

#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include "gpio_if.h"
#include "hdf_log.h"

// gpios
#define LED_GPIO_G 17 /* 绿 */
#define LED_GPIO_Y 18 /* 黄 */
#define LED_GPIO_B 22 /* 蓝 */
#define LED_GPIO_W 27 /* 白 */

#define LED_OFF 0
#define LED_ON  1

int main(void)
{
    //设置LED GPIO为输出模式
    GpioSetDir(LED_GPIO_G, GPIO_DIR_OUT);
    GpioSetDir(LED_GPIO_Y, GPIO_DIR_OUT);
    GpioSetDir(LED_GPIO_B, GPIO_DIR_OUT);
    GpioSetDir(LED_GPIO_W, GPIO_DIR_OUT);

    //设置GPIO高电平
    GpioWrite(LED_GPIO_G, LED_ON);
    GpioWrite(LED_GPIO_Y, LED_ON);
    GpioWrite(LED_GPIO_B, LED_ON);
    GpioWrite(LED_GPIO_W, LED_ON);

    getchar();

    //设置GPIO低电平
    GpioWrite(LED_GPIO_G, LED_OFF);
    GpioWrite(LED_GPIO_Y, LED_OFF);
    GpioWrite(LED_GPIO_B, LED_OFF);
    GpioWrite(LED_GPIO_W, LED_OFF);

    return 0;
}

