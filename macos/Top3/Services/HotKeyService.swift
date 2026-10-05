import AppKit
import Carbon.HIToolbox

/// A system-wide shortcut. Stored as a Carbon key code plus Carbon modifier flags.
struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = HotKey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    private static let defaultsKey = "globalHotKey"

    static var saved: HotKey {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let key = try? JSONDecoder().decode(HotKey.self, from: data) else { return .default }
        return key
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.defaultsKey) }
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// From a key event; nil unless at least one of Command, Option or Control is held.
    init?(event: NSEvent) {
        let f = event.modifierFlags
        var m: UInt32 = 0
        if f.contains(.command) { m |= UInt32(cmdKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        guard m & UInt32(cmdKey | optionKey | controlKey) != 0 else { return nil }
        self.init(keyCode: UInt32(event.keyCode), modifiers: m)
    }

    var display: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    private static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_Delete: return "Delete"
        default: break
        }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "Key \(code)" }
        let layout = unsafeBitCast(ptr, to: CFData.self)
        let bytes = unsafeBitCast(CFDataGetBytePtr(layout), to: UnsafePointer<UCKeyboardLayout>.self)
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        UCKeyTranslate(bytes, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                       OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, chars.count, &length, &chars)
        return length > 0 ? String(utf16CodeUnits: chars, count: length).uppercased() : "Key \(code)"
    }
}

/// Registers one global hotkey with Carbon. No Accessibility permission is needed.
final class HotKeyService {
    static let shared = HotKeyService()
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    @discardableResult
    func register(_ key: HotKey) -> Bool {
        installHandlerIfNeeded()
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        let id = EventHotKeyID(signature: OSType(0x5054_736B), id: 1) // "PTsk"
        let status = RegisterEventHotKey(key.keyCode, key.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        return status == noErr
    }

    /// Temporarily releases the shortcut, for example while recording a new one.
    func suspend() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { service.onPress?() }
            return noErr
        }, 1, &spec, me, &handlerRef)
    }
}
