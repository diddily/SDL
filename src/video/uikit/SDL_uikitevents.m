/*
  Simple DirectMedia Layer
  Copyright (C) 1997-2022 Sam Lantinga <slouken@libsdl.org>

  This software is provided 'as-is', without any express or implied
  warranty.  In no event will the authors be held liable for any damages
  arising from the use of this software.

  Permission is granted to anyone to use this software for any purpose,
  including commercial applications, and to alter it and redistribute it
  freely, subject to the following restrictions:

  1. The origin of this software must not be misrepresented; you must not
     claim that you wrote the original software. If you use this software
     in a product, an acknowledgment in the product documentation would be
     appreciated but is not required.
  2. Altered source versions must be plainly marked as such, and must not be
     misrepresented as being the original software.
  3. This notice may not be removed or altered from any source distribution.
*/
#include "../../SDL_internal.h"

#if SDL_VIDEO_DRIVER_UIKIT

#include "../../events/SDL_events_c.h"

#include "SDL_uikitevents.h"
#include "SDL_uikitopengles.h"
#include "SDL_uikitvideo.h"
#include "SDL_uikitwindow.h"

#import <Foundation/Foundation.h>

#if (__IPHONE_OS_VERSION_MAX_ALLOWED >= 140000) || (__APPLETV_OS_VERSION_MAX_ALLOWED >= 140000) || (__MAC_OS_VERSION_MAX_ALLOWED > 1500000)
#import <GameController/GameController.h>

#define ENABLE_GCKEYBOARD
#define ENABLE_GCMOUSE
#endif

static BOOL UIKit_EventPumpEnabled = YES;
static BOOL UIKit_EventPumpActive = NO;

void
SDL_iPhoneSetEventPump(SDL_bool enabled)
{
    UIKit_EventPumpEnabled = enabled;
}

void
UIKit_StopEvents(_THIS)
{
    dispatch_async(dispatch_get_main_queue(), ^() {
        if (UIKit_EventPumpActive) {
            UIKit_EventPumpActive = NO;
            CFRunLoopStop(CFRunLoopGetCurrent());
        }
    });
}

int
UIKit_PumpEventsUntilDate(_THIS, NSDate *expiration, bool accumulate)
{
    if (UIKit_EventPumpEnabled) {
        UIKit_EventPumpActive = YES;
        if (accumulate)
        {
            UIKit_StopEvents(_this);
        }
        while ([[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:expiration])
        {
            if (!UIKit_EventPumpActive)
            {
                break;
            }
            
            if (!accumulate)
            {
                NSComparisonResult c = [[NSDate now] compare:expiration];
                if (c == NSOrderedDescending || c == NSOrderedSame)
                {
                    break;
                }
            }
        }
        /* See the comment in the function definition. */
#if SDL_VIDEO_OPENGL_ES || SDL_VIDEO_OPENGL_ES2
        UIKit_GL_RestoreCurrentContext();
#endif
        if (!UIKit_EventPumpActive) {
            return 1;
        }
        UIKit_EventPumpActive = NO;
    }

    return 0;
}

int
UIKit_WaitEventTimeout(_THIS, int timeout)
{
    if (timeout > 0) {
        NSDate *limitDate = [NSDate dateWithTimeIntervalSinceNow: (double) timeout / 1000.0];
        return UIKit_PumpEventsUntilDate(_this, limitDate, false);
    } else if (timeout == 0) {
        return UIKit_PumpEventsUntilDate(_this, [NSDate distantPast], false);
    } else {
        return UIKit_PumpEventsUntilDate(_this, [NSDate distantFuture], false);
    }
}

void
UIKit_PumpEvents(_THIS)
{
    UIKit_PumpEventsUntilDate(_this, [NSDate distantPast], true);
}

void
UIKit_SendWakeupEvent(_THIS, SDL_Window *window)
{
    UIKit_StopEvents(_this);
}

#ifdef ENABLE_GCKEYBOARD

static SDL_bool keyboard_connected = SDL_FALSE;
static id keyboard_connect_observer = nil;
static id keyboard_disconnect_observer = nil;

static void OnGCKeyboardConnected(GCKeyboard *keyboard) API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0))
{
    keyboard_connected = SDL_TRUE;
    keyboard.keyboardInput.keyChangedHandler = ^(GCKeyboardInput *kbrd, GCControllerButtonInput *key, GCKeyCode keyCode, BOOL pressed)
    {
        SDL_SendKeyboardKey(pressed ? SDL_PRESSED : SDL_RELEASED, (SDL_Scancode)keyCode);
    };

    dispatch_queue_t queue = dispatch_queue_create( "org.libsdl.input.keyboard", DISPATCH_QUEUE_SERIAL );
    dispatch_set_target_queue( queue, dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_HIGH, 0 ) );
    keyboard.handlerQueue = queue;
}

static void OnGCKeyboardDisconnected(GCKeyboard *keyboard) API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0))
{
    keyboard.keyboardInput.keyChangedHandler = nil;
    keyboard_connected = SDL_FALSE;
}

void SDL_InitGCKeyboard(void)
{
    @autoreleasepool {
        if (@available(iOS 14.0, tvOS 14.0, *)) {
            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

            keyboard_connect_observer = [center addObserverForName:GCKeyboardDidConnectNotification
                                                            object:nil
                                                             queue:nil
                                                        usingBlock:^(NSNotification *note) {
                                                            GCKeyboard *keyboard = note.object;
                                                            OnGCKeyboardConnected(keyboard);
                                                        }];

            keyboard_disconnect_observer = [center addObserverForName:GCKeyboardDidDisconnectNotification
                                                               object:nil
                                                                queue:nil
                                                           usingBlock:^(NSNotification *note) {
                                                                GCKeyboard *keyboard = note.object;
                                                                OnGCKeyboardDisconnected(keyboard);
                                                           }];

            if (GCKeyboard.coalescedKeyboard != nil) {
                OnGCKeyboardConnected(GCKeyboard.coalescedKeyboard);
            }
        }
    }
}

SDL_bool SDL_HasGCKeyboard(void)
{
    return keyboard_connected;
}

void SDL_QuitGCKeyboard(void)
{
    @autoreleasepool {
        if (@available(iOS 14.0, tvOS 14.0, *)) {
            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

            if (keyboard_connect_observer) {
                [center removeObserver:keyboard_connect_observer name:GCKeyboardDidConnectNotification object:nil];
                keyboard_connect_observer = nil;
            }

            if (keyboard_disconnect_observer) {
                [center removeObserver:keyboard_disconnect_observer name:GCKeyboardDidDisconnectNotification object:nil];
                keyboard_disconnect_observer = nil;
            }

            if (GCKeyboard.coalescedKeyboard != nil) {
                OnGCKeyboardDisconnected(GCKeyboard.coalescedKeyboard);
            }
        }
    }
}

#else

void SDL_InitGCKeyboard(void)
{
}

SDL_bool SDL_HasGCKeyboard(void)
{
    return SDL_FALSE;
}

void SDL_QuitGCKeyboard(void)
{
}

#endif /* ENABLE_GCKEYBOARD */


#ifdef ENABLE_GCMOUSE

static int mice_connected = 0;
static id mouse_connect_observer = nil;
static id mouse_disconnect_observer = nil;
static bool mouse_relative_mode = SDL_FALSE;

static void UpdatePointerLock()
{
    SDL_VideoDevice *_this = SDL_GetVideoDevice();
    SDL_Window *window;

    for (window = _this->windows; window != NULL; window = window->next) {
        UIKit_UpdatePointerLock(_this, window);
    }
}

static int SetGCMouseRelativeMode(SDL_bool enabled)
{
    mouse_relative_mode = enabled;
    UpdatePointerLock();
    return 0;
}

static void OnGCMouseButtonChanged(SDL_MouseID mouseID, Uint8 button, BOOL pressed)
{
    SDL_SendMouseButton(SDL_GetMouseFocus(), mouseID, pressed ? SDL_PRESSED : SDL_RELEASED, button);
}

static void OnGCMouseConnected(GCMouse *mouse) API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0))
{
    SDL_MouseID mouseID = mice_connected;

    mouse.mouseInput.leftButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed)
    {
        OnGCMouseButtonChanged(mouseID, SDL_BUTTON_LEFT, pressed);
    };
    mouse.mouseInput.middleButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed)
    {
        OnGCMouseButtonChanged(mouseID, SDL_BUTTON_MIDDLE, pressed);
    };
    mouse.mouseInput.rightButton.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed)
    {
        OnGCMouseButtonChanged(mouseID, SDL_BUTTON_RIGHT, pressed);
    };

    int auxiliary_button = SDL_BUTTON_X1;
    for (GCControllerButtonInput *btn in mouse.mouseInput.auxiliaryButtons) {
        btn.pressedChangedHandler = ^(GCControllerButtonInput *button, float value, BOOL pressed)
        {
            OnGCMouseButtonChanged(mouseID, auxiliary_button, pressed);
        };
        ++auxiliary_button;
    }

    mouse.mouseInput.mouseMovedHandler = ^(GCMouseInput *mouseInput, float deltaX, float deltaY)
    {
        if (SDL_GCMouseRelativeMode()) {
            SDL_SendMouseMotion(SDL_GetMouseFocus(), mouseID, 1, (int)deltaX, -(int)deltaY);
        }
    };

    dispatch_queue_t queue = dispatch_queue_create( "org.libsdl.input.mouse", DISPATCH_QUEUE_SERIAL );
    dispatch_set_target_queue( queue, dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_HIGH, 0 ) );
    mouse.handlerQueue = queue;

    ++mice_connected;

    UpdatePointerLock();
}

static void OnGCMouseDisconnected(GCMouse *mouse) API_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0))
{
    --mice_connected;

    mouse.mouseInput.mouseMovedHandler = nil;

    mouse.mouseInput.leftButton.pressedChangedHandler = nil;
    mouse.mouseInput.middleButton.pressedChangedHandler = nil;
    mouse.mouseInput.rightButton.pressedChangedHandler = nil;

    for (GCControllerButtonInput *button in mouse.mouseInput.auxiliaryButtons) {
        button.pressedChangedHandler = nil;
    }

    UpdatePointerLock();
}

void SDL_InitGCMouse(void)
{
    @autoreleasepool {
        /* There is a bug where mouse accumulates duplicate deltas over time in iOS 14.0 */
        if (@available(iOS 14.1, tvOS 14.1, *)) {
            /* iOS will not send the new pointer touch events if you don't have this key,
             * and we need them to differentiate between mouse events and real touch events.
             */
            BOOL indirect_input_available = [[[[NSBundle mainBundle] infoDictionary] objectForKey:@"UIApplicationSupportsIndirectInputEvents"] boolValue];
            if (indirect_input_available) {
                NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

                mouse_connect_observer = [center addObserverForName:GCMouseDidConnectNotification
                                                             object:nil
                                                              queue:nil
                                                         usingBlock:^(NSNotification *note) {
                                                             GCMouse *mouse = note.object;
                                                             OnGCMouseConnected(mouse);
                                                         }];

                mouse_disconnect_observer = [center addObserverForName:GCMouseDidDisconnectNotification
                                                                object:nil
                                                                 queue:nil
                                                            usingBlock:^(NSNotification *note) {
                                                                GCMouse *mouse = note.object;
                                                                OnGCMouseDisconnected(mouse);
                                                           }];

                for (GCMouse *mouse in [GCMouse mice]) {
                    OnGCMouseConnected(mouse);
                }

                SDL_GetMouse()->SetRelativeMouseMode = SetGCMouseRelativeMode;
            } else {
                NSLog(@"You need UIApplicationSupportsIndirectInputEvents in your Info.plist for mouse support");
            }
        }
    }
}

SDL_bool SDL_HasGCMouse(void)
{
    return (mice_connected > 0);
}

SDL_bool SDL_GCMouseRelativeMode(void)
{
    return mouse_relative_mode;
}

void SDL_QuitGCMouse(void)
{
    @autoreleasepool {
        if (@available(iOS 14.1, tvOS 14.1, *)) {
            NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

            if (mouse_connect_observer) {
                [center removeObserver:mouse_connect_observer name:GCMouseDidConnectNotification object:nil];
                mouse_connect_observer = nil;
            }

            if (mouse_disconnect_observer) {
                [center removeObserver:mouse_disconnect_observer name:GCMouseDidDisconnectNotification object:nil];
                mouse_disconnect_observer = nil;
            }

            for (GCMouse *mouse in [GCMouse mice]) {
                OnGCMouseDisconnected(mouse);
            }

            SDL_GetMouse()->SetRelativeMouseMode = NULL;
        }
    }
}

#else

void SDL_InitGCMouse(void)
{
}

SDL_bool SDL_HasGCMouse(void)
{
    return SDL_FALSE;
}

SDL_bool SDL_GCMouseRelativeMode(void)
{
    return SDL_FALSE;
}

void SDL_QuitGCMouse(void)
{
}

#endif /* ENABLE_GCMOUSE */

#endif /* SDL_VIDEO_DRIVER_UIKIT */

/* vi: set ts=4 sw=4 expandtab: */
