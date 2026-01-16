package config

import "time"

// Config holds all user configuration for the application
type Config struct {
	WorkDuration      time.Duration `json:"work_duration_minutes"`
	BreakDuration     time.Duration `json:"break_duration_seconds"`
	IdleThreshold     time.Duration `json:"idle_threshold_minutes"`
	AutoStartOnLogin  bool          `json:"auto_start_on_login"`
	PauseOnFullscreen bool          `json:"pause_on_fullscreen_app"`
	NotificationSound bool          `json:"notification_sound"`
	OverlayOpacity    float64       `json:"overlay_opacity"`
	FirstRun          bool          `json:"first_run"`
}

// DefaultConfig returns a new Config with sensible defaults
func DefaultConfig() *Config {
	return &Config{
		WorkDuration:      20 * time.Minute,
		BreakDuration:     20 * time.Second,
		IdleThreshold:     5 * time.Minute,
		AutoStartOnLogin:  true,
		PauseOnFullscreen: false,
		NotificationSound: true,
		OverlayOpacity:    0.95,
		FirstRun:          true,
	}
}

// Validate checks if the configuration values are valid
func (c *Config) Validate() error {
	if c.WorkDuration < 1*time.Minute {
		return ErrInvalidWorkDuration
	}
	if c.BreakDuration < 1*time.Second {
		return ErrInvalidBreakDuration
	}
	if c.IdleThreshold < 1*time.Minute {
		return ErrInvalidIdleThreshold
	}
	if c.OverlayOpacity < 0.0 || c.OverlayOpacity > 1.0 {
		return ErrInvalidOpacity
	}
	return nil
}
