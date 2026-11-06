import Foundation
import CoreGraphics
import IOKit

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

func locateExternalDDC(for displayID: CGDirectDisplayID) -> DDCDevice? {
    guard CGDisplayIsBuiltin(displayID) == 0 else {
        return nil
    }

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
        defer {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }

        if let location = IORegistryEntryCreateCFProperty(service, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
           location == "External" {
            let chipAddr = getDDCChipAddress(for: service)
            if let avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service) {
                return AVServiceDDC(avService: avService, chipAddress: chipAddr)
            }
        }
    }

    return nil
}
