# iDRAC Connection Manager (iDRACCMan)

**Version:** 1.0.53
**Tagline:** Simplified iDRAC Access

---

# Overview

iDRAC Connection Manager (iDRACCMan) provides a single application for managing multiple Dell iDRAC systems from one interface.

Instead of opening numerous browser tabs and logging into each iDRAC individually, iDRACCMan allows you to:

* Organize servers into groups
* Launch KVM consoles and iDRAC GUIs
* Monitor health and power state
* Search across your environment
* Open multiple consoles simultaneously
* Quickly access commonly used systems

The goal is simple:

**One application. Every iDRAC.**

---

# Getting Started

## First Launch

When iDRACCMan starts, you will see:

* Connections pane on the left
* Main workspace tabs in the center
* Search and quick actions at the top
* Status bar at the bottom

Initially, no iDRACs are configured.

To begin, add one or more iDRAC systems.

---

# Adding an iDRAC

## Single System

Select:

**File → Add iDRAC**

Enter:

* IP Address or Hostname
* Username
* Password

Click:

**Connect**

iDRACCMan will:

1. Ping the iDRAC
2. Connect using Redfish
3. Collect information including:

* Service Tag
* Server Model
* Operating System Hostname
* Health Status
* Power State

Once discovery completes:

1. Select an existing group
2. Or type a new group name
3. Click **Add**

The server immediately appears in the Connections pane.

---

## Adding Multiple Systems

Multiple iDRACs can be discovered and added simultaneously.

Examples:

Comma separated:

```text
10.0.0.11,10.0.0.12,10.0.0.13
```

Semicolon separated:

```text
10.0.0.11;10.0.0.12;10.0.0.13
```

One per line:

```text
10.0.0.11
10.0.0.12
10.0.0.13
```

Each system is pinged first.

Benefits:

* Offline systems fail quickly
* Reachable systems continue to Redfish discovery
* Large batches add significantly faster

---

# Connections Pane

The Connections pane organizes servers by group.

Examples:

```text
Azure Local
    AZLNODE1
    AZLNODE2
    AZLNODE3

Production
    Server01
    Server02
```

Clicking a server selects it.

Right-clicking a server opens additional actions.

The Connections pane can be collapsed or expanded using the center toggle button.

This provides additional screen space when working with consoles or multiple tabs.

---

# Dashboard

The Dashboard provides a quick view of all configured iDRAC systems.

Information displayed includes:

* Server Name
* Address
* Service Tag
* Model
* OS Hostname
* Health
* Power State
* Group

Use the Dashboard to:

* Quickly identify unhealthy systems
* Verify power state
* Locate specific servers
* Organize large environments

---

# Opening the iDRAC GUI

Select a server.

Click:

**GUI**

The iDRAC web interface opens inside iDRACCMan.

Features include:

* Embedded browser tabs
* Multiple GUI tabs
* Automatic certificate continuation
* Automatic login support

You can work with the full iDRAC interface without opening an external browser.

---

# Opening the Console

Select a server.

Click:

**Console**

The HTML5 KVM console opens in a tab.

Features include:

* Keyboard and mouse control
* BIOS access
* Virtual media support
* Multiple console tabs
* Automatic login support

The console behaves similarly to launching the HTML5 console directly from the iDRAC.

---

# Multi View

Multi View allows several consoles to be viewed simultaneously.

To open:

1. Select a group
2. Click **Multi View**

A grid of consoles opens.

Use Multi View to:

* Monitor cluster nodes
* Watch multiple servers during maintenance
* Observe firmware updates
* Monitor reboot sequences

Double-clicking a console maximizes it.

Double-click again to restore the grid.

---

# Health Monitoring

Health information includes:

* Overall Health
* Power State
* Service Tag
* Model
* Hostname

To refresh:

**Actions → Refresh Health**

or

**Refresh All Health**

Credentials are attempted in the following order:

1. Group credentials
2. Server credentials

This allows environments using shared credentials to refresh without storing credentials on every individual server.

---

# Search

Use the search box in the upper-right corner.

Type text and:

* Press Enter
* Click the Search icon (⌕)

Search supports:

* Name
* IP Address
* Service Tag
* Model
* OS Hostname
* Group
* Health
* Power State
* Notes
* Username

Examples:

Search:

```text
AZLNODE
```

Search:

```text
100.72.44
```

Search:

```text
17WD8Y3
```

Search results open in their own tab.

Double-clicking a result opens the server console.

---

# Issues & Feedback

Click the 👤 icon.

The GitHub Issues page opens:

https://github.com/DellProSupportGse/Tools/issues

Use GitHub Issues to:

* Report bugs
* Request features
* Suggest improvements
* Submit questions
* Share feedback

---

# Help

Click the ? icon at any time.

The latest documentation opens directly from GitHub.

Because the documentation is hosted online, it can be updated without requiring a new release of iDRACCMan.

---

# Tips

* Group similar servers together.
* Use Multi View for clusters and maintenance windows.
* Collapse the Connections pane for more console space.
* Use Search instead of manually browsing large environments.
* Add multiple iDRACs at once when onboarding new systems.
* Use Refresh All Health before maintenance activities.

---

# Developed By

Dell ProSupport GSE

**iDRAC Connection Manager (iDRACCMan)**
*Simplified iDRAC Access*
