package app

import (
	"fmt"
	"log"
	"os"

	"github.com/siegfried/2020rule/internal/activity"
	"github.com/siegfried/2020rule/internal/config"
	"github.com/siegfried/2020rule/internal/overlay"
	"github.com/siegfried/2020rule/internal/stats"
	"github.com/siegfried/2020rule/internal/timer"
	"github.com/siegfried/2020rule/internal/ui"
)

// App is the main application coordinator
type App struct {
	configManager   *config.Manager
	statsStore      *stats.Store
	timerManager    *timer.Manager
	activityMonitor *activity.Monitor
	overlayWindow   *overlay.Window
	menuBar         *ui.MenuBar
	sessionID       int64
}

// New creates a new application instance
func New() (*App, error) {
	app := &App{}

	// Initialize config manager
	configManager, err := config.NewManager()
	if err != nil {
		return nil, fmt.Errorf("failed to create config manager: %w", err)
	}
	app.configManager = configManager

	// Initialize stats store
	statsStore, err := stats.NewStore()
	if err != nil {
		return nil, fmt.Errorf("failed to create stats store: %w", err)
	}
	app.statsStore = statsStore

	// Get configuration
	cfg := configManager.Get()

	// Initialize timer manager
	timerManager := timer.NewManager(cfg, statsStore)
	app.timerManager = timerManager

	// Initialize activity monitor
	activityMonitor := activity.NewMonitor(cfg)
	app.activityMonitor = activityMonitor

	// Initialize overlay window
	overlayWindow := overlay.NewWindow(cfg)
	app.overlayWindow = overlayWindow

	// Initialize menu bar
	menuBar := ui.NewMenuBar(timerManager, statsStore)
	app.menuBar = menuBar

	// Set up callbacks
	app.setupCallbacks()

	return app, nil
}

// Run starts the application
func (a *App) Run() error {
	// Start a new session
	sessionID, err := a.statsStore.StartSession()
	if err != nil {
		log.Printf("Warning: failed to start session: %v", err)
	} else {
		a.sessionID = sessionID
	}

	// Check if first run
	if a.configManager.Get().FirstRun {
		log.Println("First run detected. Welcome to 20-20-20 Rule!")
		// Update first run flag
		cfg := a.configManager.Get()
		cfg.FirstRun = false
		if err := a.configManager.Update(cfg); err != nil {
			log.Printf("Warning: failed to update first run flag: %v", err)
		}
	}

	// Start activity monitoring
	a.activityMonitor.Start()

	// Start timer
	a.timerManager.Start()

	log.Println("Application started successfully")

	// Run menu bar (this blocks until quit)
	a.menuBar.Start()

	return nil
}

// Shutdown performs cleanup before exit
func (a *App) Shutdown() {
	log.Println("Shutting down application...")

	// Stop activity monitoring
	a.activityMonitor.Stop()

	// Stop timer
	a.timerManager.Stop()

	// End session
	if a.sessionID > 0 {
		// TODO: Track paused duration
		if err := a.statsStore.EndSession(a.sessionID, 0); err != nil {
			log.Printf("Warning: failed to end session: %v", err)
		}
	}

	// Close stats store
	if err := a.statsStore.Close(); err != nil {
		log.Printf("Warning: failed to close stats store: %v", err)
	}

	log.Println("Shutdown complete")
}

// setupCallbacks configures all component callbacks
func (a *App) setupCallbacks() {
	// Timer callbacks
	a.timerManager.SetOnBreakRequired(func() {
		log.Println("Break required - showing overlay")
		cfg := a.configManager.Get()
		a.overlayWindow.Show(cfg.BreakDuration)
	})

	a.timerManager.SetOnBreakComplete(func() {
		log.Println("Break completed")
		a.overlayWindow.Hide()
	})

	a.timerManager.SetOnStateChange(func(state timer.State) {
		log.Printf("Timer state changed to: %s", state.String())
	})

	// Activity monitor callbacks
	a.activityMonitor.SetOnBecameIdle(func() {
		log.Println("User became idle - pausing timer")
		a.timerManager.PauseInactive()
	})

	a.activityMonitor.SetOnBecameActive(func() {
		log.Println("User became active - resuming timer")
		a.timerManager.ResumeFromInactive()
	})

	// Overlay callbacks
	a.overlayWindow.SetOnComplete(func() {
		log.Println("Overlay countdown complete")
		a.timerManager.CompleteBreak()
	})

	// Menu bar callbacks
	a.menuBar.SetOnPause(func() {
		log.Println("User paused timer")
		a.timerManager.Pause()
	})

	a.menuBar.SetOnResume(func() {
		log.Println("User resumed timer")
		a.timerManager.Resume()
	})

	a.menuBar.SetOnQuit(func() {
		log.Println("User requested quit")
		a.Shutdown()
		os.Exit(0)
	})
}
