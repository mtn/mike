/// Controls one device's call-facing mute state.
public protocol DeviceMuteControlling {
    func isMuted() throws -> Bool
    func setMuted(_ muted: Bool) throws
}
