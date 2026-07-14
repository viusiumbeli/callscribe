import CallScribeCore
import FluidAudio
import WhisperKit

/// Build-time check that the heavy ML dependencies compile and link on a
/// CommandLineTools-only toolchain. Real engine components arrive in M1+.
enum EngineDependencies {
    static let linked = true
}
