import Foundation

/// Format a remaining-seconds count as `m:ss` (under an hour) or `h:mm:ss`.
func formatRemaining(seconds: Int) -> String {
    let s = max(0, seconds)
    let hours = s / 3600
    let minutes = (s % 3600) / 60
    let secs = s % 60
    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
}
