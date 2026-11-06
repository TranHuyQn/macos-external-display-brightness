import Foundation
import IOKit

typealias IOAVServiceRef = UnsafeMutableRawPointer

@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> IOAVServiceRef?

@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(_ service: IOAVServiceRef, _ chipAddress: UInt32, _ dataAddress: UInt32, _ buffer: UnsafeMutableRawPointer, _ length: UInt32) -> Int32

@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ service: IOAVServiceRef, _ chipAddress: UInt32, _ dataAddress: UInt32, _ buffer: UnsafeRawPointer, _ length: UInt32) -> Int32

let DATA_ADDR: UInt32 = 0x51
let VCP_BRIGHTNESS: UInt8 = 0x10

func machErrorString(_ code: Int32) -> String {
    if let cstr = mach_error_string(code) {
        return String(cString: cstr)
    }
    return "unknown error"
}

func getDDCChipAddress(for service: io_service_t) -> UInt32 {
    var parent: io_registry_entry_t = 0
    if IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS {
        defer { IOObjectRelease(parent) }
        if let provider = IORegistryEntryCreateCFProperty(parent, "EPICProviderClass" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String {
            if provider == "AppleDCPMCDP29XX" {
                return 0xB7
            }
        }
    }
    return 0x37
}

func findExternalAVService() -> (io_service_t, IOAVServiceRef, UInt32)? {
    var iterator: io_iterator_t = 0
    guard let matching = IOServiceMatching("DCPAVServiceProxy") else {
        return nil
    }
    let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
    guard kr == KERN_SUCCESS else {
        return nil
    }
    defer { IOObjectRelease(iterator) }

    var service = IOIteratorNext(iterator)
    while service != 0 {
        if let prop = IORegistryEntryCreateCFProperty(service, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
           prop == "External" {
            let chipAddr = getDDCChipAddress(for: service)
            if let av = IOAVServiceCreateWithService(kCFAllocatorDefault, service) {
                return (service, av, chipAddr)
            }
        }
        IOObjectRelease(service)
        service = IOIteratorNext(iterator)
    }
    return nil
}

struct DDCReply {
    let current: Int
    let max: Int
    let rawHex: String
}

func parseGetVCPReply(buffer: [UInt8]) -> (current: Int, max: Int)? {
    // Standard DDC/CI Get VCP Feature Reply packet:
    // [0] = 0x6E (source address)
    // [1] = 0x88 (length = 0x80 | 8)
    // [2] = 0x02 (Get VCP Feature reply opcode)
    // [3] = 0x00 (Result code: 0x00 = No error, 0x01 = Unsupported)
    // [4] = 0x10 (VCP opcode: 0x10 = Luminance)
    // [5] = 0x00 (VCP type: 0x00 = Set parameter)
    // [6..7] = Max value (big-endian)
    // [8..9] = Current value (big-endian)
    // [10] = Checksum: 0x50 ^ buffer[0] ^ ... ^ buffer[9]

    guard buffer.count >= 11 else { return nil }

    for offset in 0...(buffer.count - 11) {
        if buffer[offset] == 0x6E && buffer[offset + 1] == 0x88 && buffer[offset + 2] == 0x02 {
            let resultCode = buffer[offset + 3]
            let vcpCode = buffer[offset + 4]

            guard resultCode == 0x00, vcpCode == VCP_BRIGHTNESS else {
                continue
            }

            // Verify checksum
            var expectedChk: UInt8 = 0x50
            for i in 0..<10 {
                expectedChk ^= buffer[offset + i]
            }

            let actualChk = buffer[offset + 10]
            guard expectedChk == actualChk else {
                print("WARNING: Checksum mismatch (expected 0x\(String(format: "%02X", expectedChk)), got 0x\(String(format: "%02X", actualChk)))")
                continue
            }

            let maxValue = (Int(buffer[offset + 6]) << 8) | Int(buffer[offset + 7])
            let curValue = (Int(buffer[offset + 8]) << 8) | Int(buffer[offset + 9])
            return (current: curValue, max: maxValue)
        }
    }
    return nil
}

func readBrightness(avService: IOAVServiceRef, chipAddr: UInt32) -> DDCReply? {
    // DDC/CI Get VCP Feature request
    // Length = 2 (0x80 | 2 = 0x82), Opcode = 0x01, VCP = 0x10
    // Checksum: (0x37 << 1) ^ DATA_ADDR ^ 0x82 ^ 0x01 ^ 0x10 = 0xAC
    let request: [UInt8] = [0x82, 0x01, VCP_BRIGHTNESS, 0xAC]

    var lastWriteError: Int32 = 0
    var writeSuccess = false

    for _ in 1...3 {
        usleep(10000)
        let ret = IOAVServiceWriteI2C(avService, chipAddr, DATA_ADDR, request, UInt32(request.count))
        lastWriteError = ret
        if ret == 0 {
            writeSuccess = true
            break
        }
        usleep(20000)
    }

    if !writeSuccess {
        let hexCode = String(format: "0x%08X", UInt32(bitPattern: lastWriteError))
        print("ERROR: IOAVServiceWriteI2C failed with IOReturn \(lastWriteError) (\(hexCode)): \(machErrorString(lastWriteError))")
        return nil
    }

    // Delay before reading response (MCDP29XX requires >= 50ms)
    usleep(50000)

    // Poll read reply with retry if monitor returns busy / null frame / zeros
    for attempt in 1...8 {
        var reply = [UInt8](repeating: 0, count: 12)
        let readRet = IOAVServiceReadI2C(avService, chipAddr, DATA_ADDR, &reply, 12)
        if readRet != 0 {
            let hexCode = String(format: "0x%08X", UInt32(bitPattern: readRet))
            print("ERROR: IOAVServiceReadI2C failed with IOReturn \(readRet) (\(hexCode)): \(machErrorString(readRet))")
            return nil
        }

        let hexDump = reply.map { String(format: "%02X", $0) }.joined(separator: " ")

        if let parsed = parseGetVCPReply(buffer: reply) {
            return DDCReply(current: parsed.current, max: parsed.max, rawHex: hexDump)
        }

        if attempt == 3 {
            // Re-send request in case monitor was busy flashing EEPROM
            _ = IOAVServiceWriteI2C(avService, chipAddr, DATA_ADDR, request, UInt32(request.count))
        }

        usleep(50000)
    }

    print("ERROR: Failed to parse valid DDC Get VCP Feature Reply")
    return nil
}

func writeBrightness(avService: IOAVServiceRef, chipAddr: UInt32, value: Int) -> Bool {
    let clampedValue = max(0, min(100, value))
    let high = UInt8((clampedValue >> 8) & 0xFF)
    let low = UInt8(clampedValue & 0xFF)

    // Standard DDC/CI Set VCP Feature:
    // length = 4 (0x80 | 4 = 0x84), opcode = 0x03, vcp = 0x10, high, low, checksum
    // Checksum: (0x37 << 1) ^ DATA_ADDR ^ 0x84 ^ 0x03 ^ 0x10 ^ high ^ low
    var packet: [UInt8] = [0x84, 0x03, VCP_BRIGHTNESS, high, low, 0]
    var chk: UInt8 = (0x37 << 1) ^ UInt8(DATA_ADDR)
    for i in 0..<5 {
        chk ^= packet[i]
    }
    packet[5] = chk

    var lastError: Int32 = 0
    for _ in 1...3 {
        usleep(10000)
        let ret = IOAVServiceWriteI2C(avService, chipAddr, DATA_ADDR, packet, UInt32(packet.count))
        lastError = ret
        if ret == 0 {
            usleep(150000) // 150ms settle time for monitor hardware write to complete
            return true
        }
        usleep(20000)
    }

    let hexCode = String(format: "0x%08X", UInt32(bitPattern: lastError))
    print("ERROR: IOAVServiceWriteI2C failed with IOReturn \(lastError) (\(hexCode)): \(machErrorString(lastError))")
    return false
}

// Main CLI entry point
guard let (serviceObj, avService, chipAddr) = findExternalAVService() else {
    print("ERROR: External DCPAVServiceProxy not found in IORegistry")
    exit(1)
}
defer {
    IOObjectRelease(serviceObj)
}

let args = CommandLine.arguments
if args.count < 2 {
    print("Usage: ddc-spike read | write <0-100>")
    exit(1)
}

switch args[1] {
case "read":
    if let res = readBrightness(avService: avService, chipAddr: chipAddr) {
        print("RAW REPLY (hex): \(res.rawHex)")
        print("current=\(res.current) max=\(res.max)")
        if res.max > 0 && res.current <= res.max {
            exit(0)
        } else {
            print("ERROR: invalid range (current > max or max <= 0)")
            exit(1)
        }
    } else {
        exit(1)
    }

case "write":
    guard args.count >= 3, let val = Int(args[2]), val >= 0, val <= 100 else {
        print("Usage: ddc-spike write <0-100>")
        exit(1)
    }
    if writeBrightness(avService: avService, chipAddr: chipAddr, value: val) {
        print("Wrote brightness: \(val)")
        exit(0)
    } else {
        exit(1)
    }

default:
    print("Unknown command: \(args[1])")
    print("Usage: ddc-spike read | write <0-100>")
    exit(1)
}
