import Foundation
import VideoToolbox
import CoreMedia

class H264Decoder {
    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    var onFrameDecoded: ((CVImageBuffer) -> Void)?

    deinit {
        if let session = session {
            VTDecompressionSessionInvalidate(session)
        }
    }

    func decodeNalu(_ nalu: Data) {
        let nalType = nalu.count > 4 ? nalu[4] & 0x1F : 0

        if nalType == 7 || nalType == 8 {
            processSPSPPS(nalu)
            return
        }

        guard let session = session else { return }

        var avccNalu = convertAnnexBToAVCC(nalu)
        guard !avccNalu.isEmpty else { return }

        var sampleBuffer: CMSampleBuffer?
        let status = createSampleBuffer(from: avccNalu, sampleBufferOut: &sampleBuffer)
        guard status == noErr, let sampleBuffer = sampleBuffer else {
            Logger.error("创建SampleBuffer失败: \(status)", category: "H264Decoder")
            return
        }

        var flags: VTDecodeInfoFlags = []
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer,
            [],
            nil,
            &flags
        )

        if decodeStatus != noErr {
            Logger.error("解码帧失败: \(decodeStatus)", category: "H264Decoder")
        }
    }

    func decodeNALUs(from data: Data) {
        let nalus = splitNALUs(data)
        for nalu in nalus {
            decodeNalu(nalu)
        }
    }

    private func processSPSPPS(_ nalu: Data) {
        let nalType = nalu.count > 4 ? nalu[4] & 0x1F : 0

        if nalType == 7 {
            let spsWithoutStartCode = nalu[4...]
            let spsArray = Array(spsWithoutStartCode)

            var newFormatDesc: CMVideoFormatDescription?
            let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: nil,
                parameterSetCount: 1,
                parameterSetPointers: [spsArray.withUnsafeBytes { $0.baseAddress! }],
                parameterSetSizes: [spsArray.count],
                nalUnitHeaderLength: 4,
                formatDescriptionOut: &newFormatDesc
            )

            if status == noErr, let desc = newFormatDesc {
                formatDescription = desc
                createDecompressionSession(formatDescription: desc)
            }
        }
    }

    private func createDecompressionSession(formatDescription: CMVideoFormatDescription) {
        if let existingSession = session {
            VTDecompressionSessionInvalidate(existingSession)
            session = nil
        }

        let destinationAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferOpenGLESCompatibilityKey as String: true
        ]

        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { (outputCallbackRefCon, _, _, _, imageBuffer, _, _) in
                guard let refCon = outputCallbackRefCon else { return }
                let decoder = Unmanaged<H264Decoder>.fromOpaque(refCon).takeUnretainedValue()
                if let imageBuffer = imageBuffer {
                    decoder.onFrameDecoded?(imageBuffer)
                }
            },
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        var callbackPtr: UnsafePointer<VTDecompressionOutputCallbackRecord>? = nil

        let status = VTDecompressionSessionCreate(
            allocator: nil,
            formatDescription: formatDescription,
            decoderSpecification: nil,
            imageBufferAttributes: destinationAttributes as CFDictionary,
            outputCallback: callbackPtr,
            decompressionSessionOut: &session
        )

        if status != noErr {
            Logger.error("创建解码会话失败: \(status)", category: "H264Decoder")
        }
    }

    private func convertAnnexBToAVCC(_ nalu: Data) -> Data {
        guard nalu.count > 4 else { return Data() }

        var startCodeLength = 0
        if nalu[0] == 0 && nalu[1] == 0 && nalu[2] == 0 && nalu[3] == 1 {
            startCodeLength = 4
        } else if nalu[0] == 0 && nalu[1] == 0 && nalu[2] == 1 {
            startCodeLength = 3
        } else {
            return Data()
        }

        let naluBody = nalu[startCodeLength...]
        var length = CFSwapInt32HostToBig(UInt32(naluBody.count))
        var result = Data(bytes: &length, count: 4)
        result.append(naluBody)
        return result
    }

    private func createSampleBuffer(from avccNalu: Data, sampleBufferOut: UnsafeMutablePointer<CMSampleBuffer?>) -> OSStatus {
        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: nil,
            memoryBlock: nil,
            blockLength: avccNalu.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: avccNalu.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == kCMBlockBufferNoErr, let block = blockBuffer else { return status }

        avccNalu.withUnsafeBytes { rawBufferPointer in
            if let baseAddress = rawBufferPointer.baseAddress {
                _ = CMBlockBufferReplaceDataBytes(
                    with: baseAddress,
                    blockBuffer: block,
                    offsetIntoDestination: 0,
                    dataLength: avccNalu.count
                )
            }
        }

        var sampleTiming = CMSampleTimingInfo(
            duration: CMTime.invalid,
            presentationTimeStamp: CMTime.invalid,
            decodeTimeStamp: CMTime.invalid
        )

        return CMSampleBufferCreate(
            allocator: nil,
            dataBuffer: block,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &sampleTiming,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: sampleBufferOut
        )
    }

    private func splitNALUs(_ data: Data) -> [Data] {
        var nalus: [Data] = []
        var searchStart = 0

        while searchStart < data.count - 3 {
            let startCodeOffset = findStartCode(in: data, from: searchStart)
            guard startCodeOffset >= 0 else { break }

            let nextStartCode = findStartCode(in: data, from: startCodeOffset + 3)
            let endOffset = nextStartCode >= 0 ? nextStartCode : data.count

            if endOffset > startCodeOffset {
                nalus.append(data[startCodeOffset..<endOffset])
            }

            searchStart = endOffset
        }

        return nalus
    }

    private func findStartCode(in data: Data, from offset: Int) -> Int {
        guard offset + 3 < data.count else { return -1 }

        for i in offset..<(data.count - 3) {
            if data[i] == 0 && data[i + 1] == 0 {
                if data[i + 2] == 1 {
                    return i
                }
                if data[i + 2] == 0 && i + 3 < data.count && data[i + 3] == 1 {
                    return i
                }
            }
        }
        return -1
    }
}
