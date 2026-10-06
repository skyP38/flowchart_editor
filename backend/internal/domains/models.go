package models

import "time"

type Project struct {
	ID         int64       `json:"id"`
	Name       string      `json:"name"`
	UserID     int64       `json:"userId"`
	DateCreate time.Time   `json:"dateCreate"`
	DateUpdate *time.Time  `json:"dateUpdate,omitempty"`
	Flowcharts []Flowchart `json:"flowcharts"`
}

type Flowchart struct {
	ID         int64          `json:"id"`
	Name       string         `json:"name"`
	Data       map[string]any `json:"data,omitempty"`
	DateCreate time.Time      `json:"dateCreate"`
	DateUpdate *time.Time     `json:"dateUpdate,omitempty"`
}
