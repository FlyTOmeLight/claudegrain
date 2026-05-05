import Foundation

public struct CostBucket: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let costUSD: Double
    public init(start: Date, end: Date, costUSD: Double) {
        self.start = start
        self.end = end
        self.costUSD = costUSD
    }
}
