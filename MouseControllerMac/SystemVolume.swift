import AudioToolbox
import CoreAudio

// Reads and sets the default output device's volume through CoreAudio.
// Some outputs (most HDMI/DisplayPort monitors) have no software volume;
// `level` is nil for those.
enum SystemVolume {

    static var level: Double? {
        guard let device = defaultOutputDevice() else { return nil }

        var address = volumeAddress
        guard AudioObjectHasProperty(device, &address) else { return nil }

        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr else { return nil }

        return Double(volume)
    }

    static var isMuted: Bool {
        guard let device = defaultOutputDevice() else { return false }

        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else { return false }

        var muted = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else { return false }

        return muted != 0
    }

    static func setLevel(_ level: Double) {
        guard let device = defaultOutputDevice() else { return }

        var address = volumeAddress
        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(device, &address, &isSettable) == noErr,
              isSettable.boolValue else { return }

        var volume = Float32(min(max(level, 0), 1))
        AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume)

        // Dragging the slider up should be audible even if the Mac was muted.
        if volume > 0 && isMuted {
            var muteAddress = muteAddress
            var unmuted = UInt32(0)
            AudioObjectSetPropertyData(device, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &unmuted)
        }
    }

    private static var volumeAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    private static func defaultOutputDevice() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &device
        )

        return status == noErr && device != 0 ? device : nil
    }
}
