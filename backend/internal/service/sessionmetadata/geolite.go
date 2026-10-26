package sessionmetadata

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/netip"
	"net/url"
	"strings"
	"time"
)

type GeoLiteClient struct {
	accountID  string
	licenseKey string
	httpClient *http.Client
}

func NewGeoLiteClient(accountID, licenseKey string) *GeoLiteClient {
	return &GeoLiteClient{
		accountID:  accountID,
		licenseKey: licenseKey,
		httpClient: &http.Client{
			Timeout: 2 * time.Second,
		},
	}
}

type geoResponse struct {
	City struct {
		Names map[string]string `json:"names"`
	} `json:"city"`

	Country struct {
		Names map[string]string `json:"names"`
	} `json:"country"`
}

func (c *GeoLiteClient) Lookup(
	ctx context.Context,
	ip string,
) (string, error) {
	addr, err := netip.ParseAddr(ip)
	if err != nil {
		return "", fmt.Errorf("invalid IP: %w", err)
	}

	addr = addr.Unmap()

	if !addr.IsValid() ||
		addr.IsLoopback() ||
		addr.IsPrivate() ||
		addr.IsUnspecified() {
		return "", fmt.Errorf("IP is not publicly routable")
	}

	endpoint := "https://geolite.info/geoip/v2.1/city/" +
		url.PathEscape(addr.String())

	req, err := http.NewRequestWithContext(
		ctx,
		http.MethodGet,
		endpoint,
		nil,
	)
	if err != nil {
		return "", err
	}

	req.SetBasicAuth(c.accountID, c.licenseKey)

	resp, err := c.httpClient.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf(
			"GeoLite API returned status %d",
			resp.StatusCode,
		)
	}

	var data geoResponse
	if err := json.NewDecoder(
		io.LimitReader(resp.Body, 1<<20),
	).Decode(&data); err != nil {
		return "", err
	}

	city := data.City.Names["ru"]
	if city == "" {
		city = data.City.Names["en"]
	}

	country := data.Country.Names["ru"]
	if country == "" {
		country = data.Country.Names["en"]
	}

	switch {
	case city != "" && country != "":
		return city + ", " + country, nil
	case city != "":
		return city, nil
	case country != "":
		return country, nil
	default:
		return "", fmt.Errorf("location not found")
	}
}

func (c *GeoLiteClient) ResolveLocation(
	ctx context.Context,
	ip string,
) string {
	if c == nil ||
		strings.TrimSpace(c.accountID) == "" ||
		strings.TrimSpace(c.licenseKey) == "" {
		return "Not recorded"
	}

	location, err := c.Lookup(ctx, ip)
	if err != nil {
		return "Not recorded"
	}

	return location
}
