package stats

import "time"

// Break represents a single break session
type Break struct {
	ID           int64     `json:"id"`
	StartedAt    time.Time `json:"started_at"`
	CompletedAt  *time.Time `json:"completed_at,omitempty"`
	WasCompleted bool      `json:"was_completed"`
	WasSkipped   bool      `json:"was_skipped"`
	DurationSecs int       `json:"duration_seconds"`
}

// DailyStats holds aggregated statistics for a single day
type DailyStats struct {
	Date             time.Time `json:"date"`
	BreaksRequired   int       `json:"breaks_required"`
	BreaksCompleted  int       `json:"breaks_completed"`
	BreaksSkipped    int       `json:"breaks_skipped"`
	TotalWorkMinutes int       `json:"total_work_minutes"`
	ComplianceRate   float64   `json:"compliance_rate"`
}

// Session represents a working session (from app start to stop)
type Session struct {
	ID                 int64      `json:"id"`
	StartedAt          time.Time  `json:"started_at"`
	EndedAt            *time.Time `json:"ended_at,omitempty"`
	PausedDurationSecs int        `json:"paused_duration_seconds"`
}

// ComplianceReport provides compliance statistics for a period
type ComplianceReport struct {
	Period          string  `json:"period"`           // "today", "week", "month"
	TotalBreaks     int     `json:"total_breaks"`
	CompletedBreaks int     `json:"completed_breaks"`
	SkippedBreaks   int     `json:"skipped_breaks"`
	ComplianceRate  float64 `json:"compliance_rate"`
	AveragePerDay   float64 `json:"average_per_day"`
}

// CalculateComplianceRate calculates the compliance rate as a percentage
func CalculateComplianceRate(completed, total int) float64 {
	if total == 0 {
		return 0.0
	}
	return float64(completed) / float64(total) * 100.0
}
