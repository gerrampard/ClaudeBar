import Foundation

/// Listens for quota status changes (e.g., to alert users).
public protocol QuotaStatusListener: Sendable {
    /// Called when a provider's quota status changes.
    func onStatusChanged(providerId: String, oldStatus: QuotaStatus, newStatus: QuotaStatus) async
}
