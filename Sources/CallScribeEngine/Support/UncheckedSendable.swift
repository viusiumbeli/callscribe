/// Transfers ownership of a non-Sendable value across a concurrency boundary.
/// Only use when the sender provably stops touching the value afterwards
/// (e.g. handing a freshly allocated audio buffer to a serial sink queue).
struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
}
