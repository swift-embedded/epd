import Hardware

public class Display {
    let spi: SPI
    let cs: DigitalOut
    let busy: DigitalIn
    let dc: DigitalOut
    let resetPin: DigitalOut

    public let width = 128
    public let height = 296

    public enum UpdateKind {
        case partial
        case full
    }

    public enum Axis: UInt8 {
        case x = 0
        case y = 1
    }

    public enum AxisUpdateKind: UInt8 {
        case decrement = 0
        case increment = 1
    }

    private enum Command: UInt8 {
        case driverOutputControl = 0x01
        case boosterSoftStartControl = 0x0C
        case gateScanStartPosition = 0x0F
        case deepSleepMode = 0x10
        case dataEntryModeSetting = 0x11
        case softwareReset = 0x12
        case temperatureSensorControl = 0x1A
        case masterActivation = 0x20
        case displayUpdateControl1 = 0x21
        case displayUpdateControl2 = 0x22
        case writeRam = 0x24
        case writeVcomRegister = 0x2C
        case writeLutRegister = 0x32
        case setDummyLinePeriod = 0x3A
        case setGateTime = 0x3B
        case borderWaveformControl = 0x3C
        case setRamXAddressStartEndPosition = 0x44
        case setRamYAddressStartEndPosition = 0x45
        case setRamXAddressCounter = 0x4E
        case setRamYAddressCounter = 0x4F
        case terminateFrameReadWrite = 0xFF
    }

    private let lutFullUpdate: ContiguousArray<UInt8> = [
        0x02, 0x02, 0x01, 0x11, 0x12, 0x12, 0x22, 0x22,
        0x66, 0x69, 0x69, 0x59, 0x58, 0x99, 0x99, 0x88,
        0x00, 0x00, 0x00, 0x00, 0xF8, 0xB4, 0x13, 0x51,
        0x35, 0x51, 0x51, 0x19, 0x01, 0x00,
    ]

    private let lutPartialUpdate: ContiguousArray<UInt8> = [
        0x10, 0x18, 0x18, 0x08, 0x18, 0x18, 0x08, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x13, 0x14, 0x44, 0x12,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]

    public init(spi: SPI,
                cs: DigitalOut, busy: DigitalIn,
                dc: DigitalOut, reset: DigitalOut) throws {
        self.spi = spi
        self.cs = cs
        self.busy = busy
        self.dc = dc
        resetPin = reset
        self.cs.set(.low)
        try setup()
    }

    private func sendCommand(_ cmd: Command) throws {
        dc.set(.low)
        try spi.transmit([cmd.rawValue])
    }

    private func sendData(_ data: ContiguousArray<UInt8>) throws {
        dc.set(.high)
        try spi.transmit(data)
    }

    public func setup() throws {
        reset()
        try sendCommand(.driverOutputControl)
        try sendData([
            UInt8((height - 1) & 0xFF),
            UInt8(((height - 1) >> 8) & 0xFF),
            0x00,
        ])
        try sendCommand(.boosterSoftStartControl)
        try sendData([0xD7, 0xD6, 0x9D])
        try sendCommand(.writeVcomRegister)
        try sendData([0x8A])
        try sendCommand(.setDummyLinePeriod)
        try sendData([0x1A])
        try sendCommand(.setGateTime)
        try sendData([0x08])
        try sendCommand(.borderWaveformControl)
        try sendData([0x03])
        try setUpdateKind(.full)
    }

    public func reset() {
        resetPin.set(.low)
        sleep(ms: 200)
        resetPin.set(.high)
        sleep(ms: 200)
    }

    public func setMemoryArea(x: ClosedRange<Int>,
                              y: ClosedRange<Int>) throws {
        try sendCommand(.setRamXAddressStartEndPosition)
        try sendData([
            UInt8(x.lowerBound >> 3),
            UInt8(x.upperBound >> 3),
        ])
        try sendCommand(.setRamYAddressStartEndPosition)
        try sendData([
            UInt8(y.lowerBound & 0xFF),
            UInt8(y.lowerBound >> 8),
            UInt8(y.upperBound & 0xFF),
            UInt8(y.upperBound >> 8),
        ])
    }

    public func setMemoryPointer(x: Int, y: Int) throws {
        try sendCommand(.setRamXAddressCounter)
        try sendData([UInt8(x >> 3)])
        try sendCommand(.setRamYAddressCounter)
        try sendData([
            UInt8(y & 0xFF),
            UInt8(y >> 8),
        ])
        waitUntilIdle()
    }

    public func setDataEntryMode(direction: (x: AxisUpdateKind, y: AxisUpdateKind), scanline: Axis) throws {
        let data = direction.x.rawValue | (direction.y.rawValue << 1) | (scanline.rawValue << 2)
        try sendCommand(.dataEntryModeSetting)
        try sendData([data])
    }

    public func waitUntilIdle() {
        while case .high = busy.get() {}
    }

    public func fill(pattern: UInt8) throws {
        try sendCommand(.writeRam)
        for _ in 0 ..< (width / 8) * height {
            try sendData([pattern])
        }
    }

    public func fill(data: ContiguousArray<UInt8>) throws {
        try sendCommand(.writeRam)
        try sendData(data)
    }

    public func displayFrame() throws {
        try sendCommand(.displayUpdateControl2)
        try sendData([0xC4])
        try sendCommand(.masterActivation)
        try sendCommand(.terminateFrameReadWrite)
        waitUntilIdle()
    }

    public func setUpdateKind(_ kind: UpdateKind) throws {
        let data: ContiguousArray<UInt8>
        switch kind {
        case .partial:
            data = lutPartialUpdate
        case .full:
            data = lutFullUpdate
        }
        try sendCommand(.writeLutRegister)
        try sendData(data)
    }
}
