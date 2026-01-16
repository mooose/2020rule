package stats

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"time"

	_ "modernc.org/sqlite"
)

const (
	appName    = "2020Rule"
	dbFileName = "stats.db"
)

// Store manages persistence of statistics using SQLite
type Store struct {
	db *sql.DB
}

// NewStore creates a new statistics store
func NewStore() (*Store, error) {
	dbPath, err := getDBPath()
	if err != nil {
		return nil, fmt.Errorf("failed to get database path: %w", err)
	}

	// Ensure directory exists
	dbDir := filepath.Dir(dbPath)
	if err := os.MkdirAll(dbDir, 0755); err != nil {
		return nil, fmt.Errorf("failed to create database directory: %w", err)
	}

	// Open database
	db, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	store := &Store{db: db}

	// Initialize schema
	if err := store.initSchema(); err != nil {
		db.Close()
		return nil, fmt.Errorf("failed to initialize schema: %w", err)
	}

	return store, nil
}

// Close closes the database connection
func (s *Store) Close() error {
	if s.db != nil {
		return s.db.Close()
	}
	return nil
}

// initSchema creates the database tables if they don't exist
func (s *Store) initSchema() error {
	schema := `
	CREATE TABLE IF NOT EXISTS breaks (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		started_at TIMESTAMP NOT NULL,
		completed_at TIMESTAMP,
		was_completed BOOLEAN DEFAULT 0,
		was_skipped BOOLEAN DEFAULT 0,
		duration_seconds INTEGER
	);

	CREATE TABLE IF NOT EXISTS daily_stats (
		date DATE PRIMARY KEY,
		breaks_required INTEGER DEFAULT 0,
		breaks_completed INTEGER DEFAULT 0,
		breaks_skipped INTEGER DEFAULT 0,
		total_work_minutes INTEGER DEFAULT 0,
		compliance_rate REAL
	);

	CREATE TABLE IF NOT EXISTS sessions (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		started_at TIMESTAMP NOT NULL,
		ended_at TIMESTAMP,
		paused_duration_seconds INTEGER DEFAULT 0
	);

	CREATE INDEX IF NOT EXISTS idx_breaks_started_at ON breaks(started_at);
	CREATE INDEX IF NOT EXISTS idx_daily_stats_date ON daily_stats(date);
	CREATE INDEX IF NOT EXISTS idx_sessions_started_at ON sessions(started_at);
	`

	_, err := s.db.Exec(schema)
	return err
}

// RecordBreakStart records the start of a break
func (s *Store) RecordBreakStart() (int64, error) {
	result, err := s.db.Exec(
		"INSERT INTO breaks (started_at) VALUES (?)",
		time.Now(),
	)
	if err != nil {
		return 0, err
	}
	return result.LastInsertId()
}

// RecordBreakComplete marks a break as completed
func (s *Store) RecordBreakComplete(breakID int64, duration time.Duration) error {
	now := time.Now()
	_, err := s.db.Exec(
		"UPDATE breaks SET completed_at = ?, was_completed = 1, duration_seconds = ? WHERE id = ?",
		now,
		int(duration.Seconds()),
		breakID,
	)
	if err != nil {
		return err
	}

	// Update daily stats
	return s.updateDailyStats(now)
}

// RecordBreakSkipped marks a break as skipped
func (s *Store) RecordBreakSkipped(breakID int64) error {
	now := time.Now()
	_, err := s.db.Exec(
		"UPDATE breaks SET completed_at = ?, was_skipped = 1 WHERE id = ?",
		now,
		breakID,
	)
	if err != nil {
		return err
	}

	// Update daily stats
	return s.updateDailyStats(now)
}

// GetBreaksByDate returns all breaks for a specific date
func (s *Store) GetBreaksByDate(date time.Time) ([]Break, error) {
	startOfDay := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, date.Location())
	endOfDay := startOfDay.Add(24 * time.Hour)

	rows, err := s.db.Query(
		`SELECT id, started_at, completed_at, was_completed, was_skipped,
		        COALESCE(duration_seconds, 0)
		 FROM breaks
		 WHERE started_at >= ? AND started_at < ?
		 ORDER BY started_at DESC`,
		startOfDay,
		endOfDay,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var breaks []Break
	for rows.Next() {
		var b Break
		var completedAt sql.NullTime
		err := rows.Scan(&b.ID, &b.StartedAt, &completedAt, &b.WasCompleted, &b.WasSkipped, &b.DurationSecs)
		if err != nil {
			return nil, err
		}
		if completedAt.Valid {
			b.CompletedAt = &completedAt.Time
		}
		breaks = append(breaks, b)
	}

	return breaks, rows.Err()
}

// GetDailyStats returns statistics for a specific date
func (s *Store) GetDailyStats(date time.Time) (*DailyStats, error) {
	dateStr := date.Format("2006-01-02")

	var stats DailyStats
	err := s.db.QueryRow(
		`SELECT date, breaks_required, breaks_completed, breaks_skipped,
		        total_work_minutes, compliance_rate
		 FROM daily_stats
		 WHERE date = ?`,
		dateStr,
	).Scan(&stats.Date, &stats.BreaksRequired, &stats.BreaksCompleted,
		&stats.BreaksSkipped, &stats.TotalWorkMinutes, &stats.ComplianceRate)

	if err == sql.ErrNoRows {
		// Return empty stats for this date
		return &DailyStats{
			Date:            date,
			BreaksRequired:  0,
			BreaksCompleted: 0,
			BreaksSkipped:   0,
			ComplianceRate:  0,
		}, nil
	}

	if err != nil {
		return nil, err
	}

	return &stats, nil
}

// GetComplianceReport generates a compliance report for a time period
func (s *Store) GetComplianceReport(period string) (*ComplianceReport, error) {
	var startDate time.Time
	now := time.Now()

	switch period {
	case "today":
		startDate = time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, now.Location())
	case "week":
		startDate = now.AddDate(0, 0, -7)
	case "month":
		startDate = now.AddDate(0, -1, 0)
	default:
		return nil, fmt.Errorf("invalid period: %s", period)
	}

	var total, completed, skipped int
	err := s.db.QueryRow(
		`SELECT
			COUNT(*) as total,
			SUM(CASE WHEN was_completed = 1 THEN 1 ELSE 0 END) as completed,
			SUM(CASE WHEN was_skipped = 1 THEN 1 ELSE 0 END) as skipped
		 FROM breaks
		 WHERE started_at >= ?`,
		startDate,
	).Scan(&total, &completed, &skipped)

	if err != nil {
		return nil, err
	}

	complianceRate := CalculateComplianceRate(completed, total)

	// Calculate days in period
	days := int(now.Sub(startDate).Hours() / 24)
	if days == 0 {
		days = 1
	}
	averagePerDay := float64(completed) / float64(days)

	return &ComplianceReport{
		Period:          period,
		TotalBreaks:     total,
		CompletedBreaks: completed,
		SkippedBreaks:   skipped,
		ComplianceRate:  complianceRate,
		AveragePerDay:   averagePerDay,
	}, nil
}

// StartSession records the start of a new application session
func (s *Store) StartSession() (int64, error) {
	result, err := s.db.Exec(
		"INSERT INTO sessions (started_at) VALUES (?)",
		time.Now(),
	)
	if err != nil {
		return 0, err
	}
	return result.LastInsertId()
}

// EndSession marks a session as ended
func (s *Store) EndSession(sessionID int64, pausedDuration time.Duration) error {
	_, err := s.db.Exec(
		"UPDATE sessions SET ended_at = ?, paused_duration_seconds = ? WHERE id = ?",
		time.Now(),
		int(pausedDuration.Seconds()),
		sessionID,
	)
	return err
}

// updateDailyStats recalculates and updates daily statistics for a given date
func (s *Store) updateDailyStats(date time.Time) error {
	dateStr := date.Format("2006-01-02")
	startOfDay := time.Date(date.Year(), date.Month(), date.Day(), 0, 0, 0, 0, date.Location())
	endOfDay := startOfDay.Add(24 * time.Hour)

	// Calculate stats from breaks table
	var required, completed, skipped int
	err := s.db.QueryRow(
		`SELECT
			COUNT(*) as required,
			SUM(CASE WHEN was_completed = 1 THEN 1 ELSE 0 END) as completed,
			SUM(CASE WHEN was_skipped = 1 THEN 1 ELSE 0 END) as skipped
		 FROM breaks
		 WHERE started_at >= ? AND started_at < ?`,
		startOfDay,
		endOfDay,
	).Scan(&required, &completed, &skipped)

	if err != nil {
		return err
	}

	complianceRate := CalculateComplianceRate(completed, required)

	// Upsert daily stats
	_, err = s.db.Exec(
		`INSERT INTO daily_stats (date, breaks_required, breaks_completed, breaks_skipped, compliance_rate)
		 VALUES (?, ?, ?, ?, ?)
		 ON CONFLICT(date) DO UPDATE SET
		   breaks_required = excluded.breaks_required,
		   breaks_completed = excluded.breaks_completed,
		   breaks_skipped = excluded.breaks_skipped,
		   compliance_rate = excluded.compliance_rate`,
		dateStr,
		required,
		completed,
		skipped,
		complianceRate,
	)

	return err
}

// getDBPath returns the path to the SQLite database file
func getDBPath() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, "Library", "Application Support", appName, dbFileName), nil
}
