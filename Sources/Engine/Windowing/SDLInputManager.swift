//
//  SDLInputManager.swift
//  InterdimensionalLlama
//
//  Created by Joseph Bennett on 17/11/16.
//
//

#if canImport(CSDL2)

import CSDL2
import CwlSignal

import DrawTools
import CDebugDrawTools

let SDLJoyStickMaxValue = Float(32767)
let JoyStickDeadZone = Float(8000)

let EmptyGamepadSlot : Int32 = -1

extension Array {
    var lowestEmptyIndex : Int? {
        return self.index(where: { $0 as! Int32 == EmptyGamepadSlot })
    }
}

#if SDL_WINDOWING

extension SDL_Keymod : OptionSet { }

public final class SDLInputManager : InputManager {
    
    public init() {
        self.setupImGui()
    }
    
    public var inputState = InputState()
    
    private var setStateOnNextUpdate : [(Device, InputSource, InputSourceState)] = []
    public private(set) var shouldQuit: Bool = false
    
    /// Mapping from an internal SDL id for a controller to our device slot.
    private var gamepadSlots = [Int32](repeating: EmptyGamepadSlot, count: DeviceType.gamepads.count)
    
    public func setupImGui() {
        let io = ImGui.io
        withUnsafeMutablePointer(to: &io.pointee.KeyMap.0) {
            let keyMap = UnsafeMutableBufferPointer(start: $0, count: Int(ImGuiKey_COUNT))
            keyMap[Int(ImGuiKey_Tab)] = Int32(SDL_SCANCODE_TAB.rawValue)
            keyMap[Int(ImGuiKey_LeftArrow)] = Int32(SDL_SCANCODE_LEFT.rawValue)
            keyMap[Int(ImGuiKey_RightArrow)] = Int32(SDL_SCANCODE_RIGHT.rawValue)
            keyMap[Int(ImGuiKey_UpArrow)] = Int32(SDL_SCANCODE_UP.rawValue)
            keyMap[Int(ImGuiKey_DownArrow)] = Int32(SDL_SCANCODE_DOWN.rawValue)
            keyMap[Int(ImGuiKey_PageUp)] = Int32(SDL_SCANCODE_PAGEUP.rawValue)
            keyMap[Int(ImGuiKey_PageDown)] = Int32(SDL_SCANCODE_PAGEDOWN.rawValue)
            keyMap[Int(ImGuiKey_Home)] = Int32(SDL_SCANCODE_HOME.rawValue)
            keyMap[Int(ImGuiKey_End)] = Int32(SDL_SCANCODE_END.rawValue)
            keyMap[Int(ImGuiKey_Insert)] = Int32(SDL_SCANCODE_INSERT.rawValue)
            keyMap[Int(ImGuiKey_Delete)] = Int32(SDL_SCANCODE_DELETE.rawValue)
            keyMap[Int(ImGuiKey_Backspace)] = Int32(SDL_SCANCODE_BACKSPACE.rawValue)
            keyMap[Int(ImGuiKey_Space)] = Int32(SDL_SCANCODE_SPACE.rawValue)
            keyMap[Int(ImGuiKey_Enter)] = Int32(SDL_SCANCODE_RETURN.rawValue)
            keyMap[Int(ImGuiKey_Escape)] = Int32(SDL_SCANCODE_ESCAPE.rawValue)
            keyMap[Int(ImGuiKey_A)] = Int32(SDL_SCANCODE_A.rawValue)
            keyMap[Int(ImGuiKey_C)] = Int32(SDL_SCANCODE_C.rawValue)
            keyMap[Int(ImGuiKey_V)] = Int32(SDL_SCANCODE_V.rawValue)
            keyMap[Int(ImGuiKey_X)] = Int32(SDL_SCANCODE_X.rawValue)
            keyMap[Int(ImGuiKey_Y)] = Int32(SDL_SCANCODE_Y.rawValue)
            keyMap[Int(ImGuiKey_Z)] = Int32(SDL_SCANCODE_Z.rawValue)
        }
    }
    
    public func signal(forSource source: InputSource) -> SignalMulti<InputSourceState> {
        return self.signal(forSource: source, onDevice: source.devices.first!)
    }
    
    public func signal(forSource source: InputSource, onDevice device: DeviceType) -> SignalMulti<InputSourceState> {
        return self.inputState[device].signal(for: source)
    }
    
    public func update(windows: [Window]) {
        self.setStateOnNextUpdate.forEach { (device, inputSource, newInputState) in device[inputSource] = newInputState }
        self.setStateOnNextUpdate.removeAll(keepingCapacity: true)
        
        self.handleEvents(windows: windows)
    }
    
    private func handleEvents(windows: [Window]) {
        var event = SDL_Event()
        while SDL_PollEvent(&event) != 0 {
            let windowId = event.window.windowID
                    
            let window = windows.first(where: { (window) -> Bool in
                return (window as! SDLWindow).sdlWindowId == windowId
            }) as! SDLWindow?
            
            if event.type == SDL_WINDOWEVENT.rawValue {
                
                window!.didReceiveEvent(event: event)
            } else {
                switch SDL_EventType(rawValue: SDL_EventType.RawValue(event.type)) {
                    
                case SDL_QUIT:
                    shouldQuit = true
                    
                case SDL_MOUSEBUTTONDOWN:
                    if let inputSource = InputSource(fromSDLMouseButton: event.button.button) {
                        let previousState = inputState[inputSource]
                        
                        if previousState != .held {
                            inputState[inputSource] = .pressed
                            setInputStateOnNextUpdate(inputSource: inputSource, newInputSourceState: .held)
                        }
                    }
                    
                case SDL_MOUSEBUTTONUP:
                    if let inputSource = InputSource(fromSDLMouseButton: event.button.button) {
                        inputState[inputSource] = .released
                        
                        setInputStateOnNextUpdate(inputSource: inputSource, newInputSourceState: .deactivated)
                    }
                    
                    
                case SDL_KEYDOWN where event.key.repeat == 0:
                    if let inputSource = InputSource(fromSDLKeySymbol: event.key.keysym, useScanCode: false) {
                        inputState[.keyboard][inputSource] = .pressed
                        setInputStateOnNextUpdate(forDevice: inputState[.keyboard], inputSource: inputSource, newInputSourceState: .held)
                    }
                    
                    if let inputSource = InputSource(fromSDLKeySymbol: event.key.keysym, useScanCode: true) {
                        inputState[.keyboardScanCode][inputSource] = .pressed
                        setInputStateOnNextUpdate(forDevice: inputState[.keyboardScanCode], inputSource: inputSource, newInputSourceState: .held)
                    }
                    
                    withUnsafeMutablePointer(to: &ImGui.io.pointee.KeysDown.0, { keysDown in
                        keysDown.advanced(by: Int(event.key.keysym.scancode.rawValue)).pointee = true
                    })
                    
                    
                    ImGui.io.pointee.KeyShift = SDL_GetModState().intersection([KMOD_LSHIFT, KMOD_RSHIFT]) != []
                    ImGui.io.pointee.KeyCtrl = SDL_GetModState().intersection([KMOD_LCTRL, KMOD_RCTRL]) != []
                    ImGui.io.pointee.KeyAlt = SDL_GetModState().intersection([KMOD_LALT, KMOD_RALT]) != []
                    ImGui.io.pointee.KeySuper = SDL_GetModState().intersection([KMOD_LGUI, KMOD_RGUI]) != []
                    
                    
                case SDL_KEYUP where event.key.repeat == 0:
                    if let inputSource = InputSource(fromSDLKeySymbol: event.key.keysym, useScanCode: false) {
                        inputState[.keyboard][inputSource] = .released
                        
                        setInputStateOnNextUpdate(forDevice: inputState[.keyboard], inputSource: inputSource, newInputSourceState: .deactivated)
                    }
                    
                    if let inputSource = InputSource(fromSDLKeySymbol: event.key.keysym, useScanCode: true) {
                        inputState[.keyboardScanCode][inputSource] = .released
                        
                        setInputStateOnNextUpdate(forDevice: inputState[.keyboardScanCode], inputSource: inputSource, newInputSourceState: .deactivated)
                    }
                    
                    withUnsafeMutablePointer(to: &ImGui.io.pointee.KeysDown.0, { keysDown in
                        keysDown.advanced(by: Int(event.key.keysym.scancode.rawValue)).pointee = false
                    })

                    ImGui.io.pointee.KeyShift = SDL_GetModState().intersection([KMOD_LSHIFT, KMOD_RSHIFT]) != []
                    ImGui.io.pointee.KeyCtrl = SDL_GetModState().intersection([KMOD_LCTRL, KMOD_RCTRL]) != []
                    ImGui.io.pointee.KeyAlt = SDL_GetModState().intersection([KMOD_LALT, KMOD_RALT]) != []
                    ImGui.io.pointee.KeySuper = SDL_GetModState().intersection([KMOD_LGUI, KMOD_RGUI]) != []
                    
                case SDL_TEXTINPUT:
                    var characters = event.text.text
                    withExtendedLifetime(characters) {
                        ImGui.io.pointee.addUTF8InputCharacters(&characters.0)
                    }
                    
                case SDL_MOUSEMOTION:
                    let windowHeight = Float(window!.dimensions.height - 1)
                    let motion = event.motion
                    inputState[.mouseX] = .value(Float(motion.x))
                    inputState[.mouseY] = .value(windowHeight - Float(motion.y))
                    inputState[.mouseXRelative] = .value(Float(motion.xrel))
                    inputState[.mouseYRelative] = .value(Float(motion.yrel))
                    
                case SDL_MOUSEWHEEL:
                    let scroll = event.wheel
                    inputState[.mouseScrollX] = .value(Float(scroll.x))
                    inputState[.mouseScrollY] = .value(Float(scroll.y))
                    
                case SDL_CONTROLLERDEVICEADDED:
                    let deviceIndex = event.cdevice.which
                    
                    guard let gamepadSlot = self.gamepadSlots.lowestEmptyIndex else {
                        print("No more controller slots available. Ignoring.")
                        break
                    }
                    
                    print("Controller connected to slot \(gamepadSlot)")
                    
                    let gameController = SDL_GameControllerOpen(deviceIndex)
                    inputState[.gamepad(slot: gamepadSlot)].connected = true
                    
                    let joyStick = SDL_GameControllerGetJoystick(gameController)
                    let instanceId = SDL_JoystickInstanceID(joyStick)
                    
                    gamepadSlots[gamepadSlot] = instanceId
                    
                case SDL_CONTROLLERDEVICEREMOVED:
                    let instanceId = event.cdevice.which
                    
                    guard let gamepadSlot = self.gamepadSlots.index(of: instanceId) else {
                        print("SDL tried to remove gamepad that we aren't keeping track of.")
                        break
                    }
                    
                    print("Controller removed from slot \(gamepadSlot)")
                    
                    let gameController = SDL_GameControllerFromInstanceID(instanceId)
                    SDL_GameControllerClose(gameController)
                    inputState[.gamepad(slot: gamepadSlot)].connected = false
                    
                    gamepadSlots[gamepadSlot] = EmptyGamepadSlot
                    
                    
                case SDL_CONTROLLERBUTTONDOWN:
                    let instanceId = event.cbutton.which
                    
                    guard let gamepadSlot = self.gamepadSlots.index(of: instanceId) else {
                        print("SDL sent button down event for untracked gamepad")
                        break
                    }
                    
                    let device = inputState[.gamepad(slot: gamepadSlot)]
                    
                    let buttonId = event.cbutton.button
                    
                    if let inputSource = InputSource(fromGameControllerButton: buttonId) {
                        let previousState = device[inputSource]
                        
                        if previousState != .held {
                            device[inputSource] = .pressed
                            setInputStateOnNextUpdate(forDevice: device, inputSource: inputSource, newInputSourceState: .held)
                        }
                    }
                    
                case SDL_CONTROLLERBUTTONUP:
                    let instanceId = event.cbutton.which
                    
                    guard let gamepadSlot = self.gamepadSlots.index(of: instanceId) else {
                        print("SDL sent button up event for untracked gamepad")
                        break
                    }
                    
                    let device = inputState[.gamepad(slot: gamepadSlot)]
                    
                    let buttonId = event.cbutton.button
                    
                    if let inputSource = InputSource(fromGameControllerButton: buttonId) {
                        inputState[.gamepad(slot: gamepadSlot)][inputSource] = .released
                        setInputStateOnNextUpdate(forDevice: device, inputSource: inputSource, newInputSourceState: .deactivated)
                    }
                    
                    
                case SDL_CONTROLLERAXISMOTION:
                    let instanceId = event.caxis.which
                    
                    guard let gamepadSlot = self.gamepadSlots.index(of: instanceId) else {
                        print("SDL sent axis motion event for untracked gamepad")
                        break
                    }
                    
                    let device = inputState[.gamepad(slot: gamepadSlot)]
                    
                    let axisId = event.caxis.axis
                    
                    if let inputSource = InputSource(fromGameControllerAxis: axisId) {
                        var value = Float(event.caxis.value)
                        
                        if (value > JoyStickDeadZone || value < -JoyStickDeadZone) {
                            if (value > JoyStickDeadZone) {
                                value -= JoyStickDeadZone
                            } else {
                                value += JoyStickDeadZone
                            }
                            
                            var normalizedValue = value/(SDLJoyStickMaxValue - JoyStickDeadZone)
                            
                            if (normalizedValue > 1.0) {
                                normalizedValue = 1.0
                            } else if (normalizedValue < -1.0) {
                                normalizedValue = -1.0
                            }
                            
                            device[inputSource] = .value(normalizedValue)
                        } else {
                            device[inputSource] = .value(0.0)
                        }
                    }
                    
                    
                default:
                    break
                }
            }
        }
    }
    
//    private func handleWindowEvent(sdlWindowEventId : SDL_WindowEventID) {
//        switch sdlWindowEventId {
//        case SDL_WINDOWEVENT_CLOSE:
//            shouldQuit = true
//        default:
//            break
//        }
//    }
    
    private func setInputStateOnNextUpdate(inputSource : InputSource, newInputSourceState: InputSourceState) {
        setInputStateOnNextUpdate(forDevice: self.inputState[inputSource.devices.first!], inputSource: inputSource, newInputSourceState: newInputSourceState)
    }
    
    private func setInputStateOnNextUpdate(forDevice: Device, inputSource : InputSource, newInputSourceState: InputSourceState) {
        setStateOnNextUpdate.append((forDevice, inputSource, newInputSourceState))
    }
}
    
#endif

struct SDLModifiers : OptionSet {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    
    public static let leftControl = SDLModifiers(rawValue: SDLModifiers.RawValue(KMOD_LCTRL.rawValue))
    public static let rightControl = SDLModifiers(rawValue: SDLModifiers.RawValue(KMOD_RCTRL.rawValue))
    
    public static let leftAlt = SDLModifiers(rawValue: SDLModifiers.RawValue(KMOD_LALT.rawValue))
    public static let rightAlt = SDLModifiers(rawValue: SDLModifiers.RawValue(KMOD_RALT.rawValue))
    public static let alt : SDLModifiers = [.leftAlt, .rightAlt]
    
    
    public static let leftShift = SDLModifiers(rawValue: SDLModifiers.RawValue(KMOD_LSHIFT.rawValue))
    public static let rightShift = SDLModifiers(rawValue: SDLModifiers.RawValue(KMOD_RSHIFT.rawValue))
    public static let shift : SDLModifiers = [.leftShift, .rightShift]
    
    
    public static let capsLock = SDLModifiers(rawValue: SDLModifiers.RawValue(KMOD_CAPS.rawValue))
    public static let numLock = SDLModifiers(rawValue: SDLModifiers.RawValue(KMOD_NUM.rawValue))
    
    // often "windows" button in Windows or "command" key on macOS
    public static let leftMeta = SDLModifiers(rawValue: SDLModifiers.RawValue(KMOD_LGUI.rawValue))
    
    // often "windows" button in Windows or "command" key on macOS
    public static let rightMeta = SDLModifiers(rawValue: SDLModifiers.RawValue(KMOD_RGUI.rawValue))
    
    public static let gui = SDLModifiers(rawValue: SDLModifiers.RawValue(KMOD_LGUI.rawValue | KMOD_RGUI.rawValue))
    
    // see https://en.wikipedia.org/wiki/AltGr_key
    public static let altGr = SDLModifiers(rawValue: SDLModifiers.RawValue(KMOD_MODE.rawValue))
}


extension InputSource {
    
    init?(fromSDLMouseButton button: UInt8) {
        switch Int32(button) {
        case SDL_BUTTON_LEFT:
            self = .mouseButtonLeft
        case SDL_BUTTON_RIGHT:
            self = .mouseButtonRight
        case SDL_BUTTON_MIDDLE:
            self = .mouseButtonMiddle
        default:
            return nil
        }
    }
    
    init?(sdlKeyCode: Int, modifiers: SDLModifiers) {
        #if os(Windows)
        let sdlKeyCode = Int32(sdlKeyCode)
        #endif
        
        switch sdlKeyCode {
            
        // special keys
        case SDLK_ESCAPE:
            self = .esc
        case SDLK_RETURN:
            self = .return
        case SDLK_TAB:
            self = .tab
        case SDLK_SPACE:
            self = .space
        case SDLK_BACKSPACE:
            self = .backspace
        case SDLK_UP:
            self = .up
        case SDLK_DOWN:
            self = .down
        case SDLK_LEFT:
            self = .left
        case SDLK_RIGHT:
            self = .right
        case SDLK_INSERT:
            self = .insert
        case SDLK_DELETE:
            self = .delete
        case SDLK_HOME:
            self = .home
        case SDLK_END:
            self = .end
        case SDLK_PAGEUP:
            self = .pageUp
        case SDLK_PAGEDOWN:
            self = .pageDown
        case SDLK_PRINTSCREEN:
            self = .print
            
        // punctuation
        case SDLK_PLUS:
            self = .plus
        case SDLK_MINUS:
            self = .minus
        case SDLK_LEFTBRACKET:
            self = .leftBracket
        case SDLK_RIGHTBRACKET:
            self = .rightBracket
        case SDLK_QUOTE:
            self = .quote
        case SDLK_COMMA:
            self = .comma
        case SDLK_PERIOD:
            self = .period
        case SDLK_SLASH:
            self = .slash
        case SDLK_BACKQUOTE:
            if modifiers.contains(.leftShift) || modifiers.contains(.rightShift) {
                self = .tilde
            } else {
                return nil
            }
            
        // function keys (f1-f9)
        case SDLK_F1:
            self = .f1
        case SDLK_F2:
            self = .f2
        case SDLK_F3:
            self = .f3
        case SDLK_F4:
            self = .f4
        case SDLK_F5:
            self = .f5
        case SDLK_F6:
            self = .f6
        case SDLK_F7:
            self = .f7
        case SDLK_F8:
            self = .f8
        case SDLK_F9:
            self = .f9
            
            
        // number pad numbers 0-9
        case SDLK_KP_0:
            self = .numPad0
        case SDLK_KP_1:
            self = .numPad1
        case SDLK_KP_2:
            self = .numPad2
        case SDLK_KP_3:
            self = .numPad3
        case SDLK_KP_4:
            self = .numPad4
        case SDLK_KP_5:
            self = .numPad5
        case SDLK_KP_6:
            self = .numPad6
        case SDLK_KP_7:
            self = .numPad7
        case SDLK_KP_8:
            self = .numPad8
        case SDLK_KP_9:
            self = .numPad9
            
        // number 0-9
        case SDLK_0:
            self = .key0
        case SDLK_1:
            self = .key1
        case SDLK_2:
            self = .key2
        case SDLK_3:
            self = .key3
        case SDLK_4:
            self = .key4
        case SDLK_5:
            self = .key5
        case SDLK_6:
            self = .key6
        case SDLK_7:
            self = .key7
        case SDLK_8:
            self = .key8
        case SDLK_9:
            self = .key9
            
        // alphabet A - Z
        case SDLK_a:
            self = .keyA
        case SDLK_b:
            self = .keyB
        case SDLK_c:
            self = .keyC
        case SDLK_d:
            self = .keyD
        case SDLK_e:
            self = .keyE
        case SDLK_f:
            self = .keyF
        case SDLK_g:
            self = .keyG
        case SDLK_h:
            self = .keyH
        case SDLK_i:
            self = .keyI
        case SDLK_j:
            self = .keyJ
        case SDLK_k:
            self = .keyK
        case SDLK_l:
            self = .keyL
        case SDLK_m:
            self = .keyM
        case SDLK_n:
            self = .keyN
        case SDLK_o:
            self = .keyO
        case SDLK_p:
            self = .keyP
        case SDLK_q:
            self = .keyQ
        case SDLK_r:
            self = .keyR
        case SDLK_s:
            self = .keyS
        case SDLK_t:
            self = .keyT
        case SDLK_u:
            self = .keyU
        case SDLK_v:
            self = .keyV
        case SDLK_w:
            self = .keyW
        case SDLK_x:
            self = .keyX
        case SDLK_y:
            self = .keyY
        case SDLK_z:
            self = .keyZ
        default:
            return nil
        }
    }
    
    init?(sdlScanCode: SDL_Scancode) {
        switch sdlScanCode {
            
        // special keys
        case SDL_SCANCODE_ESCAPE:
            self = .esc
        case SDL_SCANCODE_RETURN:
            self = .return
        case SDL_SCANCODE_TAB:
            self = .tab
        case SDL_SCANCODE_SPACE:
            self = .space
        case SDL_SCANCODE_BACKSPACE:
            self = .backspace
        case SDL_SCANCODE_UP:
            self = .up
        case SDL_SCANCODE_DOWN:
            self = .down
        case SDL_SCANCODE_LEFT:
            self = .left
        case SDL_SCANCODE_RIGHT:
            self = .right
        case SDL_SCANCODE_INSERT:
            self = .insert
        case SDL_SCANCODE_DELETE:
            self = .delete
        case SDL_SCANCODE_HOME:
            self = .home
        case SDL_SCANCODE_END:
            self = .end
        case SDL_SCANCODE_PAGEUP:
            self = .pageUp
        case SDL_SCANCODE_PAGEDOWN:
            self = .pageDown
        case SDL_SCANCODE_PRINTSCREEN:
            self = .print
            
        case SDL_SCANCODE_LSHIFT:
            self = .shift
        case SDL_SCANCODE_RSHIFT:
            self = .shift
            
        // punctuation
        case SDL_SCANCODE_EQUALS:
            self = .equals
        case SDL_SCANCODE_MINUS:
            self = .minus
        case SDL_SCANCODE_LEFTBRACKET:
            self = .leftBracket
        case SDL_SCANCODE_RIGHTBRACKET:
            self = .rightBracket
        case SDL_SCANCODE_COMMA:
            self = .comma
        case SDL_SCANCODE_PERIOD:
            self = .period
        case SDL_SCANCODE_SLASH:
            self = .slash
            
        // function keys (f1-f9)
        case SDL_SCANCODE_F1:
            self = .f1
        case SDL_SCANCODE_F2:
            self = .f2
        case SDL_SCANCODE_F3:
            self = .f3
        case SDL_SCANCODE_F4:
            self = .f4
        case SDL_SCANCODE_F5:
            self = .f5
        case SDL_SCANCODE_F6:
            self = .f6
        case SDL_SCANCODE_F7:
            self = .f7
        case SDL_SCANCODE_F8:
            self = .f8
        case SDL_SCANCODE_F9:
            self = .f9
            
            
        // number pad numbers 0-9
        case SDL_SCANCODE_KP_0:
            self = .numPad0
        case SDL_SCANCODE_KP_1:
            self = .numPad1
        case SDL_SCANCODE_KP_2:
            self = .numPad2
        case SDL_SCANCODE_KP_3:
            self = .numPad3
        case SDL_SCANCODE_KP_4:
            self = .numPad4
        case SDL_SCANCODE_KP_5:
            self = .numPad5
        case SDL_SCANCODE_KP_6:
            self = .numPad6
        case SDL_SCANCODE_KP_7:
            self = .numPad7
        case SDL_SCANCODE_KP_8:
            self = .numPad8
        case SDL_SCANCODE_KP_9:
            self = .numPad9
            
        // number 0-9
        case SDL_SCANCODE_0:
            self = .key0
        case SDL_SCANCODE_1:
            self = .key1
        case SDL_SCANCODE_2:
            self = .key2
        case SDL_SCANCODE_3:
            self = .key3
        case SDL_SCANCODE_4:
            self = .key4
        case SDL_SCANCODE_5:
            self = .key5
        case SDL_SCANCODE_6:
            self = .key6
        case SDL_SCANCODE_7:
            self = .key7
        case SDL_SCANCODE_8:
            self = .key8
        case SDL_SCANCODE_9:
            self = .key9
            
        // alphabet A - Z
        case SDL_SCANCODE_A:
            self = .keyA
        case SDL_SCANCODE_B:
            self = .keyB
        case SDL_SCANCODE_C:
            self = .keyC
        case SDL_SCANCODE_D:
            self = .keyD
        case SDL_SCANCODE_E:
            self = .keyE
        case SDL_SCANCODE_F:
            self = .keyF
        case SDL_SCANCODE_G:
            self = .keyG
        case SDL_SCANCODE_H:
            self = .keyH
        case SDL_SCANCODE_I:
            self = .keyI
        case SDL_SCANCODE_J:
            self = .keyJ
        case SDL_SCANCODE_K:
            self = .keyK
        case SDL_SCANCODE_L:
            self = .keyL
        case SDL_SCANCODE_M:
            self = .keyM
        case SDL_SCANCODE_N:
            self = .keyN
        case SDL_SCANCODE_O:
            self = .keyO
        case SDL_SCANCODE_P:
            self = .keyP
        case SDL_SCANCODE_Q:
            self = .keyQ
        case SDL_SCANCODE_R:
            self = .keyR
        case SDL_SCANCODE_S:
            self = .keyS
        case SDL_SCANCODE_T:
            self = .keyT
        case SDL_SCANCODE_U:
            self = .keyU
        case SDL_SCANCODE_V:
            self = .keyV
        case SDL_SCANCODE_W:
            self = .keyW
        case SDL_SCANCODE_X:
            self = .keyX
        case SDL_SCANCODE_Y:
            self = .keyY
        case SDL_SCANCODE_Z:
            self = .keyZ
        default:
            return nil
        }
    }
    
    init?(fromSDLKeySymbol keySymbol: SDL_Keysym, useScanCode: Bool) {
        
        if useScanCode {
            self.init(sdlScanCode: keySymbol.scancode)
        } else {
            self.init(sdlKeyCode: Int(keySymbol.sym), modifiers: SDLModifiers(rawValue: SDLModifiers.RawValue(keySymbol.mod)))
        }
    }
    
    init?(fromGameControllerButton: UInt8) {
        
        let button = SDL_GameControllerButton(rawValue: Int32(fromGameControllerButton))
        
        switch(button) {
        case SDL_CONTROLLER_BUTTON_A:
            self = .gamepadA
        case SDL_CONTROLLER_BUTTON_B:
            self = .gamepadB
        case SDL_CONTROLLER_BUTTON_X:
            self = .gamepadX
        case SDL_CONTROLLER_BUTTON_Y:
            self = .gamepadY
        case SDL_CONTROLLER_BUTTON_LEFTSTICK:
            self = .gamepadLeftStick
        case SDL_CONTROLLER_BUTTON_RIGHTSTICK:
            self = .gamepadRightStick
        case SDL_CONTROLLER_BUTTON_LEFTSHOULDER:
            self = .gamepadLeftShoulder
        case SDL_CONTROLLER_BUTTON_RIGHTSHOULDER:
            self = .gamepadRightShoulder
        case SDL_CONTROLLER_BUTTON_DPAD_UP:
            self = .gamepadUp
        case SDL_CONTROLLER_BUTTON_DPAD_DOWN:
            self = .gamepadDown
        case SDL_CONTROLLER_BUTTON_DPAD_LEFT:
            self = .gamepadLeft
        case SDL_CONTROLLER_BUTTON_DPAD_RIGHT:
            self = .gamepadRight
        case SDL_CONTROLLER_BUTTON_BACK:
            self = .gamepadBack
        case SDL_CONTROLLER_BUTTON_START:
            self = .gamepadStart
        case SDL_CONTROLLER_BUTTON_GUIDE:
            self = .gamepadGuide
        default:
            return nil
        }
    }
    
    init?(fromGameControllerAxis: UInt8) {
        
        let axis = SDL_GameControllerAxis(rawValue: Int32(fromGameControllerAxis))
        
        switch(axis) {
        case SDL_CONTROLLER_AXIS_LEFTX:
            self = .gamepadLeftAxisX
        case SDL_CONTROLLER_AXIS_LEFTY:
            self = .gamepadLeftAxisY
        case SDL_CONTROLLER_AXIS_RIGHTX:
            self = .gamepadRightAxisX
        case SDL_CONTROLLER_AXIS_RIGHTY:
            self = .gamepadRightAxisY
        case SDL_CONTROLLER_AXIS_TRIGGERLEFT:
            self = .gamepadLeftTrigger
        case SDL_CONTROLLER_AXIS_TRIGGERRIGHT:
            self = .gamepadRightTrigger
        default:
            return nil
        }
    }
    
}

#endif
