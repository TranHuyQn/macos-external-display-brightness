// Verified on macOS 26.5.2 (Darwin 25.5.0, Apple Silicon M1 Pro)
import Foundation
import IOKit
import DisplayCore

@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(_ service: CFTypeRef, _ chipAddress: UInt32, _ dataAddress: UInt32, _ buffer: UnsafeMutableRawPointer, _ length: UInt32) -> Int32

@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ service: CFTypeRef, _ chipAddress: UInt32, _ dataAddress: UInt32, _ buffer: UnsafeRawPointer, _ length: UInt32) -> Int32

final class AVServiceDDC: DDCDevice, @unchecked Sendable {
    private let avService: CFTypeRef
    private let chipAddress: UInt32
    private let dataAddress: UInt32 = 0x51
    private let vcpBrightness: UInt8 = 0x10

    private(set) var maxBrightness: Int = 100

    init(avService: CFTypeRef, chipAddress: UInt32, initialMax: Int = 100) {
        self.avService = avService
        self.chipAddress = chipAddress
        self.maxBrightness = initialMax
    }

    func readBrightness() throws -> (current: Int, max: Int) {
        // DDC/CI Get VCP Feature request
        // Length = 2 (0x80 | 2 = 0x82), Opcode = 0x01, VCP = 0x10
        // Checksum: (0x37 << 1) ^ dataAddress ^ 0x82 ^ 0x01 ^ 0x10 = 0xAC
        let request: [UInt8] = [0x82, 0x01, vcpBrightness, 0xAC]

        var writeSuccess = false
        for _ in 1...3 {
            usleep(10_000)
            let ret = IOAVServiceWriteI2C(avService, chipAddress, dataAddress, request, UInt32(request.count))
            if ret == 0 {
                writeSuccess = true
                break
            }
            usleep(20_000)
        }

        guard writeSuccess else {
            throw DDCError.readFailed
        }

        // Wait >= 50ms before reading response
        usleep(50_000)

        for attempt in 1...8 {
            var reply = [UInt8](repeating: 0, count: 12)
            let readRet = IOAVServiceReadI2C(avService, chipAddress, dataAddress, &reply, 12)
            if readRet == 0 {
                if let parsed = parseGetVCPReply(buffer: reply) {
                    guard parsed.max > 0 else {
                        throw DDCError.invalidRange
                    }
                    self.maxBrightness = parsed.max
                    return (current: parsed.current, max: parsed.max)
                }
            }

            if attempt == 3 {
                // Re-send request in case monitor was busy
                _ = IOAVServiceWriteI2C(avService, chipAddress, dataAddress, request, UInt32(request.count))
            }

            usleep(50_000)
        }

        throw DDCError.readFailed
    }

    func writeBrightness(_ value: Int) throws {
        let clampedValue = clampBrightness(value, max: maxBrightness)
        let high = UInt8((clampedValue >> 8) & 0xFF)
        let low = UInt8(clampedValue & 0xFF)

        // Standard DDC/CI Set VCP Feature:
        // length = 4 (0x80 | 4 = 0x84), opcode = 0x03, vcp = 0x10, high, low, checksum
        var packet: [UInt8] = [0x84, 0x03, vcpBrightness, high, low, 0]
        var chk: UInt8 = (0x37 << 1) ^ UInt8(dataAddress)
        for i in 0..<5 {
            chk ^= packet[i]
        }
        packet[5] = chk

        // Retry up to 2 times (3 attempts total), short delay between retries
        for attempt in 1...3 {
            if attempt > 1 {
                usleep(20_000)
            }
            let ret = IOAVServiceWriteI2C(avService, chipAddress, dataAddress, packet, UInt32(packet.count))
            if ret == 0 {
                return
            }
        }

        throw DDCError.writeFailed
    }

    private func parseGetVCPReply(buffer: [UInt8]) -> (current: Int, max: Int)? {
        guard buffer.count >= 11 else { return nil }

        for offset in 0...(buffer.count - 11) {
            if buffer[offset] == 0x6E && buffer[offset + 1] == 0x88 && buffer[offset + 2] == 0x02 {
                let resultCode = buffer[offset + 3]
                let vcpCode = buffer[offset + 4]

                guard resultCode == 0x00, vcpCode == vcpBrightness else {
                    continue
                }

                var expectedChk: UInt8 = 0x50
                for i in 0..<10 {
                    expectedChk ^= buffer[offset + i]
                }

                let actualChk = buffer[offset + 10]
                guard expectedChk == actualChk else {
                    continue
                }

                let maxValue = (Int(buffer[offset + 6]) << 8) | Int(buffer[offset + 7])
                let curValue = (Int(buffer[offset + 8]) << 8) | Int(buffer[offset + 9])
                return (current: curValue, max: maxValue)
            }
        }
        return nil
    }
}
