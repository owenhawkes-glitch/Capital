import CoreAudio
import AudioToolbox
import Foundation

/// The Mac's output volume (the one the volume keys change), read and set
/// through CoreAudio. Follows the current output device and reports changes
/// made anywhere else (keys, Control Centre, AirPods) through `onChange`.
final class SystemVolume {
    static let shared = SystemVolume()

    /// Called on the main queue with 0…100, or nil when the device has no
    /// software volume (some HDMI/USB outputs).
    var onChange: ((Double?) -> Void)?

    private var device = AudioDeviceID(kAudioObjectUnknown)
    private let queue = DispatchQueue.main
    private lazy var deviceListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.report() }
    private lazy var defaultListener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attach() }

    private init() {
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, defaultListener)
        attach()
    }

    /// 0…100, or nil if the output device can't be set in software.
    var volume: Double? {
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard device != kAudioObjectUnknown, AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return isMuted ? 0 : Double(value) * 100
    }

    func setVolume(_ percent: Double) {
        guard device != kAudioObjectUnknown else { return }
        var value = Float32(min(max(percent, 0), 100) / 100)
        var address = Self.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
        // Like the volume keys: dragging to zero mutes, dragging up unmutes.
        setMuted(percent < 0.5)
    }

    // MARK: - Private

    private var isMuted: Bool {
        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = Self.address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else { return false }
        return muted != 0
    }

    private func setMuted(_ muted: Bool) {
        var address = Self.address(kAudioDevicePropertyMute)
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue,
              isMuted != muted else { return }
        var value = UInt32(muted ? 1 : 0)
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    /// Re-subscribes when the output device changes (e.g. AirPods connect).
    private func attach() {
        if device != kAudioObjectUnknown {
            for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
                var address = Self.address(selector)
                AudioObjectRemovePropertyListenerBlock(device, &address, queue, deviceListener)
            }
        }
        var id = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        device = id
        if device != kAudioObjectUnknown {
            for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
                var address = Self.address(selector)
                if AudioObjectHasProperty(device, &address) {
                    AudioObjectAddPropertyListenerBlock(device, &address, queue, deviceListener)
                }
            }
        }
        report()
    }

    private func report() { onChange?(volume) }

    private static func address(_ selector: AudioObjectPropertySelector,
                                scope: AudioObjectPropertyScope = kAudioDevicePropertyScopeOutput) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
}
