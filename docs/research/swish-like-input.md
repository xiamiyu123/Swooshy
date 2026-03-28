# Swish-Like Input Research

Last updated: 2026-03-28

This note captures what we know about building a Swish-like interaction layer
for Sweeesh without App Store constraints.

## Bottom Line

It is realistic to build a `Swish-like experimental path` for Dock-triggered
interactions, but not by relying on public AppKit gesture APIs alone.

The likely architecture is:

1. Private or low-level multitouch input capture
2. Cursor-region hit-testing
3. Accessibility-driven Dock and window actions

The safest product strategy is still to keep this work in an isolated
experimental module until the input layer proves stable.

## What We Know

### 1. Swish publicly says it depends on low-level, non-sandboxable behavior

Swish states that it cannot ship through the Mac App Store because it requires
`low-level system operations`, and Apple only allows sandboxed apps in the
store. This is a strong signal that it is not implemented purely with ordinary
public, sandbox-friendly APIs.

Source:
- https://highlyopinionated.co/swish/

### 2. Swish publicly says it listens to cursor movement and keyboard events

Swish's legal page explicitly says the app needs to listen to `cursor movement`
and `keyboard events` to function.

Source:
- https://highlyopinionated.co/legal/

This does not prove how Swish captures trackpad gestures, but it strongly
supports the idea that region-aware interaction is part of the product design.

### 3. Public AppKit touch and gesture APIs are not enough for a background,
### global gesture tool

Apple's AppKit event guide documents touch and gesture handling in the context
of app and responder-chain event routing. That is a poor fit for a background
menubar tool that wants global, low-latency trackpad input over Dock icons,
windows, or the menu bar.

Source:
- https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/EventOverview/HandlingTouchEvents/HandlingTouchEvents.html

Inference:
- Public gesture APIs are suitable for app-local interactions
- They are not a reliable foundation for a Swish-style global gesture layer

### 4. OpenMultitouchSupport is the clearest public clue for the likely input
### direction

`OpenMultitouchSupport` is a wrapper around Apple's private
`MultitouchSupport.framework`. Its package page explicitly describes it as a
way to observe global multitouch events and notes the private framework
dependency.

Source:
- https://cocoapods.org/pods/OpenMultitouchSupport

Inference:
- A Swish-like global trackpad experience is most likely built on a similarly
  low-level input path
- This should be treated as experimental, private-framework work

## Local Feasibility Probe on This Machine

We ran a small AppleScript-based accessibility probe against the local `Dock`
process on 2026-03-28.

Observed results:

- The `Dock` process is present at:
  `/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock`
- `System Events` can see `process "Dock"`
- The process exposes one top-level `AXList`
- That list currently exposes `13` children with role `AXDockItem`
- Descriptions included application Dock items, a separator, a folder, and the
  Trash
- Positions and sizes were readable for individual Dock items

Inference:
- Dock hit-testing through Accessibility looks viable
- We should be able to map the current cursor position to a Dock item
- The harder problem is still acquiring the right gesture signal

## Recommended Architecture

### Stable mainline

Keep the current public-facing product on:

- menubar app
- Accessibility for window control
- hotkeys
- settings

This remains the reliable release path.

### Experimental branch

Add a separate experimental module for Swish-like interactions:

- `DockAccessibilityProbe`
  - enumerate `AXDockItem`
  - read position and size
  - resolve the hovered Dock item from cursor location
- `PointerTracker`
  - track `NSEvent.mouseLocation`
  - optionally combine with event taps for richer pointer/scroll context
- `MultitouchInputProbe`
  - isolate any private `MultitouchSupport.framework` integration
  - expose normalized gesture candidates to the rest of the app
- `GestureRouter`
  - map `input + region` into actions like minimize, close, quit, or cycle

## Risks

### 1. Private framework compatibility

Using `MultitouchSupport.framework` can break across macOS releases and is not
App Store safe.

### 2. Gesture ambiguity

The system already reserves some trackpad gestures. A private multitouch path
may still need careful filtering to avoid accidental triggers.

### 3. Dock behavior variation

Dock magnification, orientation, multiple displays, and hidden Dock behavior
will all affect hit-testing accuracy.

## Recommended PoC Sequence

1. Build a Dock accessibility probe
   - enumerate Dock items
   - print labels, frames, and item type
   - resolve the current hovered item

2. Build a Dock interaction prototype without raw multitouch
   - use `Command + Option + scroll` or another deliberate trigger
   - prove the region router and action router work

3. Build a private multitouch input probe
   - only log raw touches at first
   - do not connect it to product features yet

4. Add gesture recognition
   - define a tiny vocabulary first
   - example: two-finger vertical scrub over Dock item to minimize

5. Merge only if stable
   - keep unstable private-framework code behind a separate feature flag or
     experimental target

## Current Recommendation

The next concrete engineering step should be:

`implement a Dock accessibility probe before touching private multitouch code`

That keeps the unknowns isolated. If Dock hit-testing is solid, we will have
high confidence that the remaining hard problem is the input layer alone.
