package ui

import (
	"fmt"
	"time"

	"github.com/caseymrm/menuet"
	"github.com/siegfried/2020rule/internal/stats"
	"github.com/siegfried/2020rule/internal/timer"
)

// MenuBar manages the menu bar application UI
type MenuBar struct {
	timerManager *timer.Manager
	statsStore   *stats.Store
	onPause      func()
	onResume     func()
	onQuit       func()
}

// NewMenuBar creates a new menu bar UI
func NewMenuBar(tm *timer.Manager, store *stats.Store) *MenuBar {
	return &MenuBar{
		timerManager: tm,
		statsStore:   store,
	}
}

// SetOnPause sets the callback for pause action
func (m *MenuBar) SetOnPause(callback func()) {
	m.onPause = callback
}

// SetOnResume sets the callback for resume action
func (m *MenuBar) SetOnResume(callback func()) {
	m.onResume = callback
}

// SetOnQuit sets the callback for quit action
func (m *MenuBar) SetOnQuit(callback func()) {
	m.onQuit = callback
}

// Start initializes and runs the menu bar
func (m *MenuBar) Start() {
	menuet.App().Label = "com.2020rule.app"
	menuet.App().Children = m.menuItems

	// Set initial state with icon
	menuet.App().SetMenuState(&menuet.MenuState{
		Title: m.getStatusTitle(),
		Image: "icon.png",
	})

	// Update every second - start after a brief delay to ensure app is initialized
	go func() {
		time.Sleep(500 * time.Millisecond) // Wait for RunApplication to initialize
		ticker := time.NewTicker(1 * time.Second)
		defer ticker.Stop()

		for range ticker.C {
			menuet.App().SetMenuState(&menuet.MenuState{
				Title: m.getStatusTitle(),
				Image: "icon.png",
			})
		}
	}()

	menuet.App().RunApplication()
}

// getStatusTitle returns the current status for the menu bar
func (m *MenuBar) getStatusTitle() string {
	state := m.timerManager.GetState()

	switch state {
	case timer.StateRunning:
		remaining := m.timerManager.GetTimeUntilBreak()
		minutes := int(remaining.Minutes())
		seconds := int(remaining.Seconds()) % 60
		return fmt.Sprintf("⏱ %02d:%02d", minutes, seconds)

	case timer.StateBreakRequired:
		remaining := m.timerManager.GetBreakTimeRemaining()
		seconds := int(remaining.Seconds())
		return fmt.Sprintf("👁 Pause: %ds", seconds)

	case timer.StatePausedManual:
		return "⏸ Pausiert"

	case timer.StatePausedInactive:
		return "💤 Inaktiv"

	default:
		return "20-20-20"
	}
}

// menuItems returns the menu items for the menu bar
func (m *MenuBar) menuItems() []menuet.MenuItem {
	state := m.timerManager.GetState()

	items := []menuet.MenuItem{
		{
			Text: m.getStatusInfo(),
		},
		{
			Type: menuet.Separator,
		},
	}

	// Add pause/resume button
	if state == timer.StateRunning {
		items = append(items, menuet.MenuItem{
			Text: "Pausieren",
			Clicked: func() {
				if m.onPause != nil {
					m.onPause()
				}
			},
		})
	} else if state == timer.StatePausedManual || state == timer.StatePausedInactive {
		items = append(items, menuet.MenuItem{
			Text: "Fortsetzen",
			Clicked: func() {
				if m.onResume != nil {
					m.onResume()
				}
			},
		})
	}

	// Add statistics menu item
	items = append(items, menuet.MenuItem{
		Type: menuet.Separator,
	})

	items = append(items, menuet.MenuItem{
		Text: "Statistiken",
		Children: func() []menuet.MenuItem {
			return m.getStatisticsMenu()
		},
	})

	// Add quit button
	items = append(items, menuet.MenuItem{
		Type: menuet.Separator,
	})

	items = append(items, menuet.MenuItem{
		Text: "Beenden",
		Clicked: func() {
			if m.onQuit != nil {
				m.onQuit()
			}
		},
	})

	return items
}

// getStatusInfo returns detailed status information
func (m *MenuBar) getStatusInfo() string {
	state := m.timerManager.GetState()

	switch state {
	case timer.StateRunning:
		remaining := m.timerManager.GetTimeUntilBreak()
		minutes := int(remaining.Minutes())
		seconds := int(remaining.Seconds()) % 60
		return fmt.Sprintf("Nächste Pause in: %02d:%02d", minutes, seconds)

	case timer.StateBreakRequired:
		return "Zeit für eine Augenpause!"

	case timer.StatePausedManual:
		return "Timer ist pausiert"

	case timer.StatePausedInactive:
		return "Timer pausiert (inaktiv)"

	default:
		return "20-20-20 Regel"
	}
}

// getStatisticsMenu returns the statistics submenu
func (m *MenuBar) getStatisticsMenu() []menuet.MenuItem {
	// Get today's stats
	todayReport, err := m.statsStore.GetComplianceReport("today")
	var todayText string
	if err == nil {
		todayText = fmt.Sprintf("Heute: %d/%d (%.0f%%)",
			todayReport.CompletedBreaks,
			todayReport.TotalBreaks,
			todayReport.ComplianceRate)
	} else {
		todayText = "Heute: Keine Daten"
	}

	// Get week stats
	weekReport, err := m.statsStore.GetComplianceReport("week")
	var weekText string
	if err == nil {
		weekText = fmt.Sprintf("Woche: %d/%d (%.0f%%)",
			weekReport.CompletedBreaks,
			weekReport.TotalBreaks,
			weekReport.ComplianceRate)
	} else {
		weekText = "Woche: Keine Daten"
	}

	// Get month stats
	monthReport, err := m.statsStore.GetComplianceReport("month")
	var monthText string
	if err == nil {
		monthText = fmt.Sprintf("Monat: %d/%d (%.0f%%)",
			monthReport.CompletedBreaks,
			monthReport.TotalBreaks,
			monthReport.ComplianceRate)
	} else {
		monthText = "Monat: Keine Daten"
	}

	return []menuet.MenuItem{
		{
			Text: todayText,
		},
		{
			Text: weekText,
		},
		{
			Text: monthText,
		},
	}
}
