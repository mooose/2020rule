package config

import "errors"

var (
	// ErrInvalidWorkDuration is returned when work duration is less than 1 minute
	ErrInvalidWorkDuration = errors.New("work duration must be at least 1 minute")

	// ErrInvalidBreakDuration is returned when break duration is less than 1 second
	ErrInvalidBreakDuration = errors.New("break duration must be at least 1 second")

	// ErrInvalidIdleThreshold is returned when idle threshold is less than 1 minute
	ErrInvalidIdleThreshold = errors.New("idle threshold must be at least 1 minute")

	// ErrInvalidOpacity is returned when overlay opacity is not between 0.0 and 1.0
	ErrInvalidOpacity = errors.New("overlay opacity must be between 0.0 and 1.0")

	// ErrConfigNotFound is returned when the config file doesn't exist
	ErrConfigNotFound = errors.New("config file not found")

	// ErrConfigDirCreation is returned when the config directory cannot be created
	ErrConfigDirCreation = errors.New("failed to create config directory")
)
