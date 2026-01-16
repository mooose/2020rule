package activity

import (
	"sync"
	"time"

	"github.com/lextoumbourou/idle"
	"github.com/siegfried/2020rule/internal/config"
)

// Monitor tracks user activity and detects idle periods
type Monitor struct {
	config          *config.Config
	pollInterval    time.Duration
	isIdle          bool
	ticker          *time.Ticker
	stopChan        chan struct{}
	onBecameIdle    func()
	onBecameActive  func()
	mu              sync.Mutex
	running         bool
}

// NewMonitor creates a new activity monitor
func NewMonitor(cfg *config.Config) *Monitor {
	return &Monitor{
		config:       cfg,
		pollInterval: 10 * time.Second, // Poll every 10 seconds
		stopChan:     make(chan struct{}),
		isIdle:       false,
	}
}

// Start begins monitoring user activity
func (m *Monitor) Start() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if m.running {
		return
	}

	m.running = true
	m.ticker = time.NewTicker(m.pollInterval)

	go m.monitorLoop()
}

// Stop stops monitoring user activity
func (m *Monitor) Stop() {
	m.mu.Lock()
	defer m.mu.Unlock()

	if !m.running {
		return
	}

	m.running = false
	close(m.stopChan)

	if m.ticker != nil {
		m.ticker.Stop()
		m.ticker = nil
	}
}

// IsIdle returns whether the user is currently idle
func (m *Monitor) IsIdle() bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	return m.isIdle
}

// SetOnBecameIdle sets the callback for when the user becomes idle
func (m *Monitor) SetOnBecameIdle(callback func()) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.onBecameIdle = callback
}

// SetOnBecameActive sets the callback for when the user becomes active
func (m *Monitor) SetOnBecameActive(callback func()) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.onBecameActive = callback
}

// UpdateConfig updates the configuration
func (m *Monitor) UpdateConfig(cfg *config.Config) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.config = cfg
}

// monitorLoop is the main monitoring loop
func (m *Monitor) monitorLoop() {
	for {
		select {
		case <-m.ticker.C:
			m.checkIdleStatus()
		case <-m.stopChan:
			return
		}
	}
}

// checkIdleStatus checks the current idle time and updates state
func (m *Monitor) checkIdleStatus() {
	idleDuration, err := idle.Get()
	if err != nil {
		// If we can't get idle time, assume active
		m.setActive()
		return
	}

	m.mu.Lock()
	threshold := m.config.IdleThreshold
	wasIdle := m.isIdle
	m.mu.Unlock()

	if idleDuration >= threshold {
		if !wasIdle {
			m.setIdle()
		}
	} else {
		if wasIdle {
			m.setActive()
		}
	}
}

// setIdle marks the user as idle and triggers callback
func (m *Monitor) setIdle() {
	m.mu.Lock()
	if m.isIdle {
		m.mu.Unlock()
		return
	}
	m.isIdle = true
	callback := m.onBecameIdle
	m.mu.Unlock()

	if callback != nil {
		callback()
	}
}

// setActive marks the user as active and triggers callback
func (m *Monitor) setActive() {
	m.mu.Lock()
	if !m.isIdle {
		m.mu.Unlock()
		return
	}
	m.isIdle = false
	callback := m.onBecameActive
	m.mu.Unlock()

	if callback != nil {
		callback()
	}
}
