package timer

import (
	"sync"
	"time"

	"github.com/siegfried/2020rule/internal/config"
	"github.com/siegfried/2020rule/internal/stats"
)

// State represents the current state of the timer
type State int

const (
	// StateRunning means the work timer is actively running
	StateRunning State = iota
	// StateBreakRequired means it's time for a break
	StateBreakRequired
	// StatePausedManual means the user manually paused the timer
	StatePausedManual
	// StatePausedInactive means the timer auto-paused due to inactivity
	StatePausedInactive
)

// String returns a human-readable string for the state
func (s State) String() string {
	switch s {
	case StateRunning:
		return "Running"
	case StateBreakRequired:
		return "Break Required"
	case StatePausedManual:
		return "Paused"
	case StatePausedInactive:
		return "Paused (Idle)"
	default:
		return "Unknown"
	}
}

// Manager handles the timer logic and state transitions
type Manager struct {
	state          State
	config         *config.Config
	statsStore     *stats.Store
	currentTimer   *time.Timer
	workStartTime  time.Time
	breakStartTime time.Time
	currentBreakID int64
	elapsed        time.Duration
	pauseTime      time.Time

	// Callbacks
	onBreakRequired func()
	onBreakComplete func()
	onStateChange   func(State)

	mu sync.Mutex
}

// NewManager creates a new timer manager
func NewManager(cfg *config.Config, store *stats.Store) *Manager {
	return &Manager{
		state:      StatePausedManual,
		config:     cfg,
		statsStore: store,
	}
}

// Start begins the timer
func (m *Manager) Start() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.state == StateRunning || m.state == StateBreakRequired {
		return // Already running or in break
	}

	m.state = StateRunning
	m.workStartTime = time.Now()
	m.elapsed = 0

	m.scheduleWorkTimer()
	m.notifyStateChange()
}

// Pause manually pauses the timer
func (m *Manager) Pause() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.state != StateRunning {
		return
	}

	m.stopCurrentTimer()
	m.pauseTime = time.Now()
	m.elapsed += time.Since(m.workStartTime)
	m.state = StatePausedManual
	m.notifyStateChange()
}

// Resume resumes the timer from pause
func (m *Manager) Resume() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.state != StatePausedManual && m.state != StatePausedInactive {
		return
	}

	m.state = StateRunning
	m.workStartTime = time.Now()
	m.scheduleWorkTimer()
	m.notifyStateChange()
}

// PauseInactive pauses the timer due to user inactivity
func (m *Manager) PauseInactive() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.state != StateRunning {
		return
	}

	m.stopCurrentTimer()
	m.pauseTime = time.Now()
	m.elapsed += time.Since(m.workStartTime)
	m.state = StatePausedInactive
	m.notifyStateChange()
}

// ResumeFromInactive resumes the timer after inactivity
func (m *Manager) ResumeFromInactive() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.state != StatePausedInactive {
		return
	}

	m.state = StateRunning
	m.workStartTime = time.Now()
	m.scheduleWorkTimer()
	m.notifyStateChange()
}

// CompleteBreak marks the current break as completed
func (m *Manager) CompleteBreak() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.state != StateBreakRequired {
		return
	}

	// Record break completion
	if m.statsStore != nil && m.currentBreakID > 0 {
		duration := time.Since(m.breakStartTime)
		m.statsStore.RecordBreakComplete(m.currentBreakID, duration)
	}

	// Reset to running state
	m.state = StateRunning
	m.workStartTime = time.Now()
	m.elapsed = 0
	m.currentBreakID = 0

	m.scheduleWorkTimer()
	m.notifyStateChange()

	if m.onBreakComplete != nil {
		m.onBreakComplete()
	}
}

// SkipBreak skips the current break (not recommended, but allowed)
func (m *Manager) SkipBreak() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.state != StateBreakRequired {
		return
	}

	// Record break as skipped
	if m.statsStore != nil && m.currentBreakID > 0 {
		m.statsStore.RecordBreakSkipped(m.currentBreakID)
	}

	// Reset to running state
	m.state = StateRunning
	m.workStartTime = time.Now()
	m.elapsed = 0
	m.currentBreakID = 0

	m.scheduleWorkTimer()
	m.notifyStateChange()
}

// GetState returns the current state
func (m *Manager) GetState() State {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.state
}

// GetTimeUntilBreak returns the remaining time until the next break
func (m *Manager) GetTimeUntilBreak() time.Duration {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.state != StateRunning {
		return 0
	}

	totalElapsed := m.elapsed + time.Since(m.workStartTime)
	remaining := m.config.WorkDuration - totalElapsed

	if remaining < 0 {
		return 0
	}

	return remaining
}

// GetBreakTimeRemaining returns the remaining time in the current break
func (m *Manager) GetBreakTimeRemaining() time.Duration {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.state != StateBreakRequired {
		return 0
	}

	elapsed := time.Since(m.breakStartTime)
	remaining := m.config.BreakDuration - elapsed

	if remaining < 0 {
		return 0
	}

	return remaining
}

// SetOnBreakRequired sets the callback for when a break is required
func (m *Manager) SetOnBreakRequired(callback func()) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.onBreakRequired = callback
}

// SetOnBreakComplete sets the callback for when a break is completed
func (m *Manager) SetOnBreakComplete(callback func()) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.onBreakComplete = callback
}

// SetOnStateChange sets the callback for when state changes
func (m *Manager) SetOnStateChange(callback func(State)) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.onStateChange = callback
}

// UpdateConfig updates the configuration
func (m *Manager) UpdateConfig(cfg *config.Config) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.config = cfg
}

// Stop stops the timer completely
func (m *Manager) Stop() {
	m.mu.Lock()
	defer m.mu.Unlock()

	m.stopCurrentTimer()
	m.state = StatePausedManual
	m.elapsed = 0
	m.notifyStateChange()
}

// scheduleWorkTimer schedules a timer for the work duration
func (m *Manager) scheduleWorkTimer() {
	m.stopCurrentTimer()

	remaining := m.config.WorkDuration - m.elapsed
	if remaining <= 0 {
		m.triggerBreak()
		return
	}

	m.currentTimer = time.AfterFunc(remaining, func() {
		m.mu.Lock()
		defer m.mu.Unlock()

		if m.state == StateRunning {
			m.triggerBreak()
		}
	})
}

// triggerBreak initiates a break
func (m *Manager) triggerBreak() {
	// Record break start
	if m.statsStore != nil {
		breakID, err := m.statsStore.RecordBreakStart()
		if err == nil {
			m.currentBreakID = breakID
		}
	}

	m.state = StateBreakRequired
	m.breakStartTime = time.Now()

	// Note: Break completion is handled by the overlay's onComplete callback
	// which calls CompleteBreak(). We don't schedule a timer here to avoid
	// race conditions between the overlay countdown and a separate timer.

	m.notifyStateChange()

	if m.onBreakRequired != nil {
		m.onBreakRequired()
	}
}

// stopCurrentTimer stops the current timer if it exists
func (m *Manager) stopCurrentTimer() {
	if m.currentTimer != nil {
		m.currentTimer.Stop()
		m.currentTimer = nil
	}
}

// notifyStateChange calls the state change callback if set
func (m *Manager) notifyStateChange() {
	if m.onStateChange != nil {
		state := m.state
		go m.onStateChange(state) // Call in goroutine to avoid blocking
	}
}
