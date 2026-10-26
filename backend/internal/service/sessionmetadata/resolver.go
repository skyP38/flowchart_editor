package sessionmetadata

import (
	"context"
	"strings"

	"github.com/skyP38/flowchart_editor/backend/internal/domains"
)

type LocationLookup interface {
	ResolveLocation(ctx context.Context, ip string) string
}

type Resolver struct {
	geo LocationLookup
}

func NewResolver(geo LocationLookup) *Resolver {
	return &Resolver{
		geo: geo,
	}
}

func (r *Resolver) Resolve(
    userAgent string,
    _ string,
) domains.SessionMetadata {
    return domains.SessionMetadata{
        DeviceName: detectDeviceName(userAgent),
        Location:   "Not recorded",
    }
}

func detectDeviceName(userAgent string) string {
	ua := strings.ToLower(userAgent)

	if ua == "" {
		return "Unknown device"
	}

	browser := ""
	switch {
	case strings.Contains(ua, "edg/"),
		strings.Contains(ua, "edgios/"):
		browser = "Edge"
	case strings.Contains(ua, "opr/"):
		browser = "Opera"
	case strings.Contains(ua, "firefox/"),
		strings.Contains(ua, "fxios/"):
		browser = "Firefox"
	case strings.Contains(ua, "chrome/"),
		strings.Contains(ua, "crios/"):
		browser = "Chrome"
	case strings.Contains(ua, "safari/"):
		browser = "Safari"
	}

	osName := ""
	switch {
	case strings.Contains(ua, "android"):
		osName = "Android"
	case strings.Contains(ua, "iphone"),
		strings.Contains(ua, "ipad"),
		strings.Contains(ua, "ipod"),
		strings.Contains(ua, "cpu iphone os"),
		strings.Contains(ua, "cpu os"):
		osName = "iOS"
	case strings.Contains(ua, "windows"):
		osName = "Windows"
	case strings.Contains(ua, "macintosh"),
		strings.Contains(ua, "mac os x"):
		osName = "macOS"
	case strings.Contains(ua, "linux"):
		osName = "Linux"
	}

	if browser == "" && osName == "" {
		return "Unknown device"
	}
	if browser == "" {
		return osName
	}
	if osName == "" {
		return browser
	}

	return browser + " on " + osName
}
