package sessionmetadata

import (
	"fmt"
	"strings"
	geodecode "github.com/sdwillbrand/GeoDecode"
)

func CoordinatesToLocation(latitude, longitude float64) string {
	if latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180 {
		return "Not recorded"
	}

	location := geodecode.FindLocation([2]float64{latitude, longitude}, false)
	
	if location == nil {return "Not recorded"}
	city := strings.TrimSpace(location.City)
	country := strings.TrimSpace(location.Country)
	if city != "" && country != "" {
		return fmt.Sprintf("%s, %s", city, country)
	}
	if city != "" {return city}
	if country != "" {return country}
	return "Not recorded"
}
