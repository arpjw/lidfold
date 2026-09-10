import Foundation
import IOKit.hid

/// Reads the undocumented Apple lid-orientation HID device.
///
/// This is intentionally isolated because Apple may change the report shape or
/// device matching keys in a future macOS release.
final class HingeAngleSensor {
    private let manager: IOHIDManager
    private var device: IOHIDDevice?

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let match: [String: Any] = [
            kIOHIDVendorIDKey as String: 0x05AC,
            kIOHIDDeviceUsagePageKey as String: 0x0020,
            kIOHIDDeviceUsageKey as String: 0x008A,
        ]
        IOHIDManagerSetDeviceMatching(manager, match as CFDictionary)
        IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        device = Self.firstReadableDevice(in: manager)

        if let device {
            IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
    }

    deinit {
        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func readAngle() -> Double? {
        guard let device else { return nil }

        var report = [UInt8](repeating: 0, count: 8)
        var reportLength = report.count
        let result = report.withUnsafeMutableBytes { bytes in
            IOHIDDeviceGetReport(
                device,
                kIOHIDReportTypeFeature,
                1,
                bytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                &reportLength
            )
        }

        guard result == kIOReturnSuccess else { return nil }
        return HingeReport.decode(report.prefix(reportLength))
    }

    private static func firstReadableDevice(in manager: IOHIDManager) -> IOHIDDevice? {
        guard let deviceSet = IOHIDManagerCopyDevices(manager) else { return nil }

        let count = CFSetGetCount(deviceSet)
        var pointers = [UnsafeRawPointer?](repeating: nil, count: count)
        CFSetGetValues(deviceSet, &pointers)

        for pointer in pointers.compactMap({ $0 }) {
            let candidate = unsafeBitCast(pointer, to: IOHIDDevice.self)
            guard IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess
            else { continue }
            defer { IOHIDDeviceClose(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) }

            var report = [UInt8](repeating: 0, count: 8)
            var reportLength = report.count
            let result = report.withUnsafeMutableBytes { bytes in
                IOHIDDeviceGetReport(
                    candidate,
                    kIOHIDReportTypeFeature,
                    1,
                    bytes.baseAddress!.assumingMemoryBound(to: UInt8.self),
                    &reportLength
                )
            }
            if result == kIOReturnSuccess, HingeReport.decode(report.prefix(reportLength)) != nil {
                return candidate
            }
        }
        return nil
    }
}

enum HingeReport {
    static func decode<C: Collection>(_ bytes: C) -> Double? where C.Element == UInt8 {
        let values = Array(bytes)
        guard values.count >= 3 else { return nil }

        let rawAngle = UInt16(values[1]) | (UInt16(values[2]) << 8)
        let angle = Double(rawAngle)
        guard (0...180).contains(angle) else { return nil }
        return angle
    }
}
