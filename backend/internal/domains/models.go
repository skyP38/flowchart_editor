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

type Session struct {
	ID          int64      `json:"id"`
	UserID      int64      `json:"userId"`
	DateCreate  time.Time  `json:"dateCreate"`
	IsActive    bool       `json:"isActive"`
	ClosingDate *time.Time `json:"closingDate,omitempty"`
}

type User struct {
	ID        int64     `json:"id"`
	FIO       string    `json:"fio"`
	Login     string    `json:"login"`
	Status    bool      `json:"status"`
	DateCreate time.Time `json:"dateCreate"`
}

