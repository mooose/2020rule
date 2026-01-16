package config

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

const (
	appName        = "2020Rule"
	configFileName = "config.json"
)

// Manager handles loading and saving configuration
type Manager struct {
	configPath string
	config     *Config
}

// NewManager creates a new config manager
func NewManager() (*Manager, error) {
	configDir, err := getConfigDir()
	if err != nil {
		return nil, fmt.Errorf("failed to get config directory: %w", err)
	}

	// Ensure config directory exists
	if err := os.MkdirAll(configDir, 0755); err != nil {
		return nil, fmt.Errorf("%w: %v", ErrConfigDirCreation, err)
	}

	configPath := filepath.Join(configDir, configFileName)

	m := &Manager{
		configPath: configPath,
	}

	// Load or create default config
	if err := m.Load(); err != nil {
		if os.IsNotExist(err) {
			// Create default config
			m.config = DefaultConfig()
			if err := m.Save(); err != nil {
				return nil, fmt.Errorf("failed to save default config: %w", err)
			}
		} else {
			return nil, fmt.Errorf("failed to load config: %w", err)
		}
	}

	return m, nil
}

// Load reads the configuration from disk
func (m *Manager) Load() error {
	data, err := os.ReadFile(m.configPath)
	if err != nil {
		return err
	}

	// Parse JSON with custom unmarshaling for durations
	var raw map[string]interface{}
	if err := json.Unmarshal(data, &raw); err != nil {
		return fmt.Errorf("failed to unmarshal config: %w", err)
	}

	config := DefaultConfig()

	// Parse duration fields (stored as minutes/seconds in JSON)
	if v, ok := raw["work_duration_minutes"].(float64); ok {
		config.WorkDuration = minutesToDuration(v)
	}
	if v, ok := raw["break_duration_seconds"].(float64); ok {
		config.BreakDuration = secondsToDuration(v)
	}
	if v, ok := raw["idle_threshold_minutes"].(float64); ok {
		config.IdleThreshold = minutesToDuration(v)
	}
	if v, ok := raw["auto_start_on_login"].(bool); ok {
		config.AutoStartOnLogin = v
	}
	if v, ok := raw["pause_on_fullscreen_app"].(bool); ok {
		config.PauseOnFullscreen = v
	}
	if v, ok := raw["notification_sound"].(bool); ok {
		config.NotificationSound = v
	}
	if v, ok := raw["overlay_opacity"].(float64); ok {
		config.OverlayOpacity = v
	}
	if v, ok := raw["first_run"].(bool); ok {
		config.FirstRun = v
	}

	// Validate the loaded config
	if err := config.Validate(); err != nil {
		return fmt.Errorf("invalid config: %w", err)
	}

	m.config = config
	return nil
}

// Save writes the configuration to disk
func (m *Manager) Save() error {
	if m.config == nil {
		m.config = DefaultConfig()
	}

	// Validate before saving
	if err := m.config.Validate(); err != nil {
		return fmt.Errorf("invalid config: %w", err)
	}

	// Convert to JSON-friendly format
	data := map[string]interface{}{
		"work_duration_minutes":    durationToMinutes(m.config.WorkDuration),
		"break_duration_seconds":   durationToSeconds(m.config.BreakDuration),
		"idle_threshold_minutes":   durationToMinutes(m.config.IdleThreshold),
		"auto_start_on_login":      m.config.AutoStartOnLogin,
		"pause_on_fullscreen_app":  m.config.PauseOnFullscreen,
		"notification_sound":       m.config.NotificationSound,
		"overlay_opacity":          m.config.OverlayOpacity,
		"first_run":                m.config.FirstRun,
	}

	jsonData, err := json.MarshalIndent(data, "", "  ")
	if err != nil {
		return fmt.Errorf("failed to marshal config: %w", err)
	}

	if err := os.WriteFile(m.configPath, jsonData, 0644); err != nil {
		return fmt.Errorf("failed to write config file: %w", err)
	}

	return nil
}

// Get returns the current configuration
func (m *Manager) Get() *Config {
	if m.config == nil {
		m.config = DefaultConfig()
	}
	return m.config
}

// Update updates the configuration and saves it
func (m *Manager) Update(config *Config) error {
	if err := config.Validate(); err != nil {
		return err
	}
	m.config = config
	return m.Save()
}

// getConfigDir returns the application's config directory
// On macOS: ~/Library/Application Support/2020Rule
func getConfigDir() (string, error) {
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, "Library", "Application Support", appName), nil
}

// Helper functions for duration conversion
func minutesToDuration(minutes float64) time.Duration {
	return time.Duration(minutes * float64(time.Minute))
}

func secondsToDuration(seconds float64) time.Duration {
	return time.Duration(seconds * float64(time.Second))
}

func durationToMinutes(d time.Duration) float64 {
	return d.Minutes()
}

func durationToSeconds(d time.Duration) float64 {
	return d.Seconds()
}
