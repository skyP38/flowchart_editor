package domains

import "strings"

// NormalizeLogin приводит логин к каноническом виду: без пробелов в нижнем регистре
func NormalizeLogin(s string) string {
	return strings.ToLower(strings.TrimSpace(s))
}
