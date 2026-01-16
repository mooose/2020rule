package overlay

import (
	"fmt"
	"sync"
	"time"

	"github.com/progrium/darwinkit/dispatch"
	"github.com/progrium/darwinkit/macos/appkit"
	"github.com/progrium/darwinkit/macos/foundation"
	"github.com/progrium/darwinkit/objc"

	"github.com/siegfried/2020rule/internal/config"
)

// Window manages the fullscreen overlay for breaks
type Window struct {
	config        *config.Config
	isShowing     bool
	mu            sync.Mutex
	windows       []appkit.Window
	labels        []appkit.TextField
	ticker        *time.Ticker
	stopChan      chan struct{}
	onComplete    func()
	remainingSecs int
}

// NewWindow creates a new overlay window manager
func NewWindow(cfg *config.Config) *Window {
	return &Window{
		config:   cfg,
		stopChan: make(chan struct{}, 1),
	}
}

// Show displays the overlay on all screens
func (w *Window) Show(duration time.Duration) {
	w.mu.Lock()
	if w.isShowing {
		w.mu.Unlock()
		return
	}
	w.isShowing = true
	w.remainingSecs = int(duration.Seconds())

	// Drain any leftover stop signal from previous countdown
	select {
	case <-w.stopChan:
	default:
	}
	w.mu.Unlock()

	// Create overlay windows on main thread
	dispatch.MainQueue().DispatchAsync(func() {
		w.createOverlayWindows()
		w.startCountdown()
	})
}

// Hide closes all overlay windows
func (w *Window) Hide() {
	w.mu.Lock()
	if !w.isShowing {
		w.mu.Unlock()
		return
	}
	w.isShowing = false

	if w.ticker != nil {
		w.ticker.Stop()
		w.ticker = nil
	}

	// Signal the countdown goroutine to stop
	select {
	case w.stopChan <- struct{}{}:
	default:
		// Channel might be full or goroutine already stopped
	}
	w.mu.Unlock()

	// Close windows on main thread
	dispatch.MainQueue().DispatchAsync(func() {
		w.closeOverlayWindows()
	})
}

// SetOnComplete sets the callback for when the countdown completes
func (w *Window) SetOnComplete(callback func()) {
	w.onComplete = callback
}

// UpdateConfig updates the configuration
func (w *Window) UpdateConfig(cfg *config.Config) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.config = cfg
}

// createOverlayWindows creates a fullscreen overlay on each screen
func (w *Window) createOverlayWindows() {
	screens := appkit.Screen_Screens()

	w.windows = make([]appkit.Window, 0, len(screens))
	w.labels = make([]appkit.TextField, 0, len(screens))

	for _, screen := range screens {
		frame := screen.Frame()

		// Create borderless window (styleMask = 0)
		win := appkit.NewWindowWithContentRectStyleMaskBackingDefer(
			frame,
			0, // Borderless
			appkit.BackingStoreBuffered,
			false,
		)
		objc.Retain(&win)

		// Configure window for overlay behavior
		win.SetOpaque(false)
		win.SetHasShadow(false)

		// Set background color with configured opacity
		opacity := w.config.OverlayOpacity
		if opacity <= 0 {
			opacity = 0.95
		}
		bgColor := appkit.Color_ColorWithSRGBRedGreenBlueAlpha(0.0, 0.0, 0.0, opacity)
		win.SetBackgroundColor(bgColor)

		// Set window level to float above everything
		win.SetLevel(appkit.ScreenSaverWindowLevel)

		// Allow window to appear on all spaces including fullscreen apps
		win.SetCollectionBehavior(
			appkit.WindowCollectionBehaviorCanJoinAllSpaces |
				appkit.WindowCollectionBehaviorStationary |
				appkit.WindowCollectionBehaviorFullScreenAuxiliary,
		)

		// Create content view with countdown label
		contentView := w.createContentView(frame)
		win.SetContentView(contentView)

		// Show window
		win.OrderFrontRegardless()

		w.windows = append(w.windows, win)
	}
}

// createContentView creates the view with countdown text
func (w *Window) createContentView(frame foundation.Rect) appkit.View {
	// Create container view
	view := appkit.NewViewWithFrame(frame)

	// Create main message label
	messageLabel := appkit.NewLabel("👀 Schau in die Ferne!")
	messageLabel.SetAlignment(appkit.TextAlignmentCenter)
	messageLabel.SetTextColor(appkit.Color_WhiteColor())
	messageLabel.SetFont(appkit.Font_SystemFontOfSizeWeight(48, appkit.FontWeightBold))
	messageLabel.SetBackgroundColor(appkit.Color_ClearColor())
	messageLabel.SetBezeled(false)
	messageLabel.SetEditable(false)

	// Position message in upper third
	msgWidth := 800.0
	msgHeight := 60.0
	msgX := (frame.Size.Width - msgWidth) / 2
	msgY := frame.Size.Height*0.6 - msgHeight/2
	messageLabel.SetFrame(foundation.Rect{
		Origin: foundation.Point{X: msgX, Y: msgY},
		Size:   foundation.Size{Width: msgWidth, Height: msgHeight},
	})

	// Create countdown label
	countdownLabel := appkit.NewLabel(fmt.Sprintf("%d", w.remainingSecs))
	countdownLabel.SetAlignment(appkit.TextAlignmentCenter)
	countdownLabel.SetTextColor(appkit.Color_WhiteColor())
	countdownLabel.SetFont(appkit.Font_SystemFontOfSizeWeight(120, appkit.FontWeightLight))
	countdownLabel.SetBackgroundColor(appkit.Color_ClearColor())
	countdownLabel.SetBezeled(false)
	countdownLabel.SetEditable(false)

	// Position countdown in center
	labelWidth := 300.0
	labelHeight := 140.0
	labelX := (frame.Size.Width - labelWidth) / 2
	labelY := (frame.Size.Height - labelHeight) / 2
	countdownLabel.SetFrame(foundation.Rect{
		Origin: foundation.Point{X: labelX, Y: labelY},
		Size:   foundation.Size{Width: labelWidth, Height: labelHeight},
	})

	// Create subtitle label
	subtitleLabel := appkit.NewLabel("Sekunden verbleibend")
	subtitleLabel.SetAlignment(appkit.TextAlignmentCenter)
	subtitleLabel.SetTextColor(appkit.Color_ColorWithSRGBRedGreenBlueAlpha(1.0, 1.0, 1.0, 0.7))
	subtitleLabel.SetFont(appkit.Font_SystemFontOfSizeWeight(24, appkit.FontWeightRegular))
	subtitleLabel.SetBackgroundColor(appkit.Color_ClearColor())
	subtitleLabel.SetBezeled(false)
	subtitleLabel.SetEditable(false)

	// Position subtitle below countdown
	subWidth := 400.0
	subHeight := 30.0
	subX := (frame.Size.Width - subWidth) / 2
	subY := labelY - 50
	subtitleLabel.SetFrame(foundation.Rect{
		Origin: foundation.Point{X: subX, Y: subY},
		Size:   foundation.Size{Width: subWidth, Height: subHeight},
	})

	// Add labels to view
	view.AddSubview(messageLabel)
	view.AddSubview(countdownLabel)
	view.AddSubview(subtitleLabel)

	// Store countdown label reference for updates
	w.labels = append(w.labels, countdownLabel)

	return view
}

// closeOverlayWindows closes and releases all overlay windows
func (w *Window) closeOverlayWindows() {
	for _, win := range w.windows {
		win.OrderOut(nil)
		win.Close()
	}
	w.windows = nil
	w.labels = nil
}

// startCountdown begins the countdown timer
func (w *Window) startCountdown() {
	w.ticker = time.NewTicker(1 * time.Second)

	go func() {
		for {
			select {
			case <-w.ticker.C:
				w.mu.Lock()
				if !w.isShowing {
					w.mu.Unlock()
					return
				}
				w.remainingSecs--
				remaining := w.remainingSecs
				labels := w.labels
				w.mu.Unlock()

				// Update labels on main thread
				dispatch.MainQueue().DispatchAsync(func() {
					for _, label := range labels {
						label.SetStringValue(fmt.Sprintf("%d", remaining))
					}
				})

				// Check if countdown complete
				if remaining <= 0 {
					w.mu.Lock()
					if w.ticker != nil {
						w.ticker.Stop()
					}
					w.mu.Unlock()
					w.Hide()
					if w.onComplete != nil {
						w.onComplete()
					}
					return
				}

			case <-w.stopChan:
				return
			}
		}
	}()
}
